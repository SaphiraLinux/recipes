#!/bin/sh
# ensure-identity.sh [--disable] FRAGMENT — additive, idempotent
# system-identity reconciler, plus its removal counterpart.
#
# Called ONLY from makepkg-generated package scripts, with the
# package's own accounts.d fragment. Ensure mode (post-install,
# post-upgrade) makes sure every declared group, user, locked shadow
# entry, and state directory exists; never modifies, reorders, or
# rehashes anything already present.
#
# Disable mode (--disable, post-deinstall) sanitizes WITHOUT deleting:
# a removed package must never leave its historical service account
# usable for login. For every declared user found on the system it
# forces the shadow entry locked ('!') and the shell to
# /sbin/nologin, preserving UID, GID, home, and every other field;
# groups stay present and reserved; state directories are untouched
# (never walked, never chowned, never removed); fixed IDs are never
# recycled. Anything already absent is a silent no-op, so repeats are
# harmless. A present user with a DIFFERENT UID, or a present group
# with a DIFFERENT GID, is fatal: disable never touches an unrelated
# account merely because a name collides.
#
# Fragment syntax (strict; anything else fails closed):
#   group <name> <gid>
#   user <name> <uid> <primary-group> <home> <shell>
#   dir <path> <mode> <owner> <group>
# Blank lines and '#' comments are ignored.
#
# Rules:
# - one package owns each declared identity; a user/group name or numeric
#   ID that already exists with DIFFERENT attributes is a fatal conflict
#   (the publish gate should have caught it — this is the live backstop).
#   An already-present entry with MATCHING attributes converges silently:
#   hand-provisioned local accounts (e.g. qmail's fixed IDs) never block
#   an install, they just make it a no-op.
# - reservations are kind-specific: the USER root and UID 0 are
#   refused; the GROUPS root, wheel and spokes and GIDs 0, 1 and 2
#   are refused, as is anchoring any service user to those groups
#   as primary. (spokes is group-only: a user merely named spokes
#   is not forbidden by this rule.) Root provisioning belongs
#   exclusively to the base seed and firstboot; this tool can
#   neither create, converge with, nor disable those identities.
# - packaged IDs are created only in 0..887 (preferred 0..199;
#   200..887 is reserved expansion - accepted here, allocation
#   preference is enforced at build and publish time, not on the
#   live box). 888..999 belong to local user services and 1000+ to
#   humans: creation there refuses, while convergence with an
#   existing entry is always allowed.
# - a primary group that is neither declared in this fragment nor already
#   present may still be satisfied from the accounts.tsv base-seed map
#   (shipped by this same package set at usr/share/saphira/accounts.tsv).
#   Anything else is fatal — the package must declare what it owns.
# - shadow entries this tool creates are locked ('!'). An existing shadow
#   entry that is locked ('!', '*', '!...') is left alone. An existing
#   entry with a usable password hash is FATAL: this tool must never
#   represent, alter, or overwrite login credentials.
# - directory reconciliation is non-recursive: missing leading components
#   are created with default modes, and only the final leaf gets the
#   declared mode/ownership (changed only when different, to stay
#   idempotent). Existing trees are never walked.
# - all account-file mutation happens under an exclusive lock so
#   concurrent package installs cannot interleave appends.
#
# Target root: the live system when run from apk scripts (which execute
# inside the installation root). SAPHIRA_ENSURE_ROOT overrides for tests.

set -eu

# Argument parsing lives below die() so usage failures report cleanly.
ROOT=${SAPHIRA_ENSURE_ROOT:-/}
PASSWD=$ROOT/etc/passwd
GROUPF=$ROOT/etc/group
SHADOW=$ROOT/etc/shadow
TSV=$ROOT/usr/share/saphira/accounts.tsv
LOCKF=$ROOT/etc/.saphira-accounts.lock

log()
{
	printf 'ensure-identity: %s\n' "$*"
}

die()
{
	printf 'ensure-identity: ERROR: %s\n' "$*" >&2
	exit 1
}

MODE=ensure
case ${1:-} in
	--disable) MODE=disable; shift ;;
	-*) die "usage: ensure-identity.sh [--disable] FRAGMENT" ;;
esac
FRAGMENT=${1:?usage: ensure-identity.sh [--disable] FRAGMENT}

test -f "$FRAGMENT" || die "fragment is missing: $FRAGMENT"
for f in "$PASSWD" "$GROUPF" "$SHADOW"; do
	test -f "$f" || die "account database is missing: $f"
done

# --- exclusive lock (flock when available, atomic mkdir fallback) ---
lockdir=
if command -v flock >/dev/null 2>&1; then
	# shellcheck disable=SC2094
	: > "$LOCKF" 2>/dev/null || die "cannot write lock file: $LOCKF"
	exec 9> "$LOCKF" || die "cannot open lock file: $LOCKF"
	flock 9 || die "cannot acquire account lock"
else
	lockdir=$LOCKF.mkdir
	while ! mkdir "$lockdir" 2>/dev/null; do
		# sleep may not exist on a bare target; without it this
		# degrades to a spin, which is harmless for the
		# millisecond-scale hold time of an append-only update.
		sleep 1 2>/dev/null || true
	done
fi
unlock()
{
	if [ -n "$lockdir" ]; then
		rmdir "$lockdir" 2>/dev/null || true
	fi
}
trap unlock EXIT HUP INT TERM

# --- lookups (shell builtins only: no awk/getent/useradd dependency.
# External tools used below are coreutils (stat/mkdir/chown/chmod/dirname)
# plus flock-or-mkdir for locking; makepkg adds bash+coreutils to the
# dependency set of every fragment-carrying package so apk installs
# them before these scripts can run) ---
field()
{
	# field N LINE -> Nth colon-separated field (empty when absent).
	_n=$1
	set -f
	# shellcheck disable=SC2086
	IFS=:; set -- $2
	# shellcheck disable=SC1083,SC2086
	eval "printf '%s' \"\${$_n-}\""
}

find_line()
{
	# find_line FILE NAME -> first line starting 'NAME:', or nothing.
	while IFS= read -r line || [ -n "$line" ]; do
		case $line in
			"$2":*) printf '%s\n' "$line"; return 0 ;;
		esac
	done < "$1"
	return 1
}

find_uid()
{
	# find_uid UID -> owning user name, or nothing.
	while IFS= read -r line || [ -n "$line" ]; do
		[ "$(field 3 "$line")" = "$1" ] || continue
		field 1 "$line"
		return 0
	done < "$PASSWD"
	return 1
}

find_gid()
{
	# find_gid GID -> owning group name, or nothing.
	while IFS= read -r line || [ -n "$line" ]; do
		[ "$(field 3 "$line")" = "$1" ] || continue
		field 1 "$line"
		return 0
	done < "$GROUPF"
	return 1
}

passwd_entry() { find_line "$PASSWD" "$1" || true; }
group_entry() { find_line "$GROUPF" "$1" || true; }
shadow_entry() { find_line "$SHADOW" "$1" || true; }
uid_taken() { find_uid "$1" || true; }
gid_taken() { find_gid "$1" || true; }
tsv_group_gid()
{
	test -f "$TSV" || return 1
	while IFS='	' read -r tname ttype tid _ _ _ _ || [ -n "$tname" ]; do
		if [ "$tname" = "$1" ] && [ "$ttype" = group ]; then
			printf '%s' "$tid"
			return 0
		fi
	done < "$TSV"
	return 1
}

valid_name()
{
	case $1 in
		''|-*|*[!a-zA-Z0-9_.-]*) return 1 ;;
	esac
	return 0
}

reserved_identity()
{
	# reserved_identity KIND NAME ID — kind-specific foundation
	# reservations, refused in BOTH modes at validation and apply
	# time. Root provisioning belongs exclusively to the base seed
	# and firstboot. spokes is group-only: a user merely named
	# spokes (or wheel) is not forbidden by this rule, but no group
	# may own GID 0, 1, or 2 under any name.
	kind=$1
	name=$2
	id=$3
	case $kind in
		user)
			case $name in
				root) die "refusing user $name: root is a reserved system identity, packages must never own it" ;;
			esac
			[ "$id" != 0 ] ||
				die "refusing user $name: UID 0 is reserved"
			;;
		group)
			case $name in
				root|wheel|spokes) die "refusing group $name: reserved foundational group, packages must never own it" ;;
			esac
			case $id in
				0|1|2) die "refusing group $name: GID $id is a reserved foundation ID" ;;
			esac
			;;
	esac
}

ensure_group()
{
	name=$1
	gid=$2
	valid_name "$name" || die "invalid group name: $name"
	case $gid in
		''|*[!0-9]*|0*[!0-9]*) die "invalid GID: $gid" ;;
	esac
	# strip leading zeros for numeric comparison
	gid=$((gid + 0))
	reserved_identity group "$name" "$gid"
	existing=$(group_entry "$name")
	if [ -n "$existing" ]; then
		[ "$(field 3 "$existing")" = "$gid" ] ||
			die "group conflict: $name exists with different GID"
		log "group $name ($gid) already present"
		return 0
	fi
	# Packaged range only on creation: 888..999 belong to local user
	# services and 1000+ to humans, so this tool never mints IDs there
	# (converging with an already-present entry above is fine and is
	# handled by the early return). A hand-provisioned local account
	# (e.g. qmail's fixed IDs) with matching attributes converges
	# silently instead of blocking the install.
	[ "$gid" -ge 0 ] && [ "$gid" -le 887 ] || die "GID outside packaged range 0..887: $gid"
	owner=$(gid_taken "$gid")
	[ -z "$owner" ] || die "GID conflict: $gid already owned by group $owner"
	printf '%s:x:%s:\n' "$name" "$gid" >> "$GROUPF" ||
		die "cannot append group $name"
	log "group $name ($gid) created"
}

ensure_user()
{
	name=$1
	uid=$2
	primary=$3
	home=$4
	shell=$5
	valid_name "$name" || die "invalid user name: $name"
	valid_name "$primary" || die "invalid primary group name: $primary"
	case $uid in
		''|*[!0-9]*) die "invalid UID: $uid" ;;
	esac
	uid=$((uid + 0))
	reserved_identity user "$name" "$uid"
	case $primary in
		root|wheel|spokes) die "refusing user $name: primary group $primary is a reserved foundation group" ;;
	esac
	case $home in
		/*) ;;
		*) die "home must be absolute: $home" ;;
	esac
	case $shell in
		/*) ;;
		*) die "shell must be absolute: $shell" ;;
	esac
	existing=$(passwd_entry "$name")
	primary_gid=$(group_gid "$primary")
	if [ -n "$existing" ]; then
		[ -n "$primary_gid" ] ||
			die "user conflict: $name exists but primary group $primary is absent"
		[ "$(field 3 "$existing")" = "$uid" ] ||
			die "user conflict: $name exists with different UID"
		[ "$(field 4 "$existing")" = "$primary_gid" ] ||
			die "user conflict: $name exists with different primary group"
		log "user $name ($uid) already present"
		ensure_shadow "$name"
		ensure_home "$home" "$uid" "$primary"
		return 0
	fi
	# Packaged range only on creation (see ensure_group): a locally
	# hand-provisioned account with matching attributes converges
	# above via the early return and never reaches this refusal.
	[ "$uid" -ge 0 ] && [ "$uid" -le 887 ] || die "UID outside packaged range 0..887: $uid"
	owner=$(uid_taken "$uid")
	[ -z "$owner" ] || die "UID conflict: $uid already owned by user $owner"
	# primary group: fragment-declared, already present, or base-seeded.
	if [ -z "$(group_entry "$primary")" ]; then
		tsv_gid=$(tsv_group_gid "$primary") || tsv_gid=
		if [ -n "$tsv_gid" ]; then
			ensure_group "$primary" "$tsv_gid"
		else
			die "primary group is not declared, present, or base-seeded: $primary"
		fi
	fi
	gid=$(group_gid "$primary")
	printf '%s:x:%s:%s:%s:%s:%s\n' \
		"$name" "$uid" "$gid" "$name" "$home" "$shell" >> "$PASSWD" ||
		die "cannot append user $name"
	log "user $name ($uid:$gid) created"
	ensure_shadow "$name"
	ensure_home "$home" "$uid" "$primary"
}

group_gid()
{
	field 3 "$(group_entry "$1")"
}

ensure_shadow()
{
	name=$1
	existing=$(shadow_entry "$name")
	if [ -n "$existing" ]; then
		hash=$(field 2 "$existing")
		case $hash in
			''|'!'|'!'*|'*') log "shadow $name already locked" ;;
			*) die "shadow $name has a usable password hash; refusing to touch credentials" ;;
		esac
		return 0
	fi
	printf '%s:%s:0:0:99999:7:::\n' "$name" '!' >> "$SHADOW" ||
		die "cannot append shadow $name"
	log "shadow $name locked"
}

ensure_leaf()
{
	path=$1
	mode=$2
	owner=$3
	group=$4
	# create missing leading components with default modes; only the
	# leaf receives declared mode/ownership, and only when different.
	parent=$(dirname -- "$path")
	if [ ! -d "$ROOT$parent" ]; then
		mkdir -p "$ROOT$parent" || die "cannot create $parent"
	fi
	if [ ! -e "$ROOT$path" ] && [ ! -L "$ROOT$path" ]; then
		mkdir "$ROOT$path" || die "cannot create $path"
		log "directory $path created"
	fi
	[ -d "$ROOT$path" ] || die "not a directory: $path"
	current_mode=$(stat -c '%a' "$ROOT$path") || die "cannot stat $path"
	current_owner=$(stat -c '%u:%g' "$ROOT$path") || die "cannot stat $path"
	want_owner=$(id_numeric "$owner"); want_group=$(id_numeric_group "$group")
	[ -n "$want_owner" ] || die "unknown owner: $owner"
	[ -n "$want_group" ] || die "unknown group: $group"
	if [ "$current_owner" != "$want_owner:$want_group" ]; then
		chown "$want_owner:$want_group" "$ROOT$path" ||
			die "cannot set ownership on $path"
		log "directory $path ownership set to $want_owner:$want_group"
	fi
	# normalize declared mode (accept 755 or 0755) for comparison
	want_mode=$mode
	while [ "$want_mode" != "${want_mode#0}" ]; do
		want_mode=${want_mode#0}
	done
	[ -n "$want_mode" ] || want_mode=0
	if [ "$current_mode" != "$want_mode" ]; then
		chmod "$mode" "$ROOT$path" || die "cannot set mode on $path"
		log "directory $path mode set to $mode"
	fi
}

id_numeric()
{
	case $1 in
		''|*[!0-9]*) field 3 "$(passwd_entry "$1")" ;;
		*) printf '%s' "$1" ;;
	esac
}

id_numeric_group()
{
	case $1 in
		''|*[!0-9]*) group_gid "$1" ;;
		*) printf '%s' "$1" ;;
	esac
}

ensure_home()
{
	home=$1
	uid=$2
	primary=$3
	case $home in
		/var/empty|/nonexistent|/dev/null) return 0 ;;
	esac
	ensure_leaf "$home" 755 "$uid" "$(group_gid "$primary")"
}

# --- disable mode (--disable): sanitize without deleting ---
#
# Phase 1 (disable_validate) is pure reads: every stanza is shape-
# checked and every present identity is conflict-checked before
# anything is written, so a refusal leaves the databases untouched.
# Phase 2 (disable_apply) forces locked shadow + nologin shell on
# verified identities, retains groups, and ignores state entirely.
frag_groups=

frag_gid()
{
	# frag_gid NAME -> GID declared for NAME in this fragment, or empty.
	search=" $frag_groups"
	case $search in
		*" $1:"*)
			tail=${search#*" $1:"}
			printf '%s' "${tail%% *}"
			;;
	esac
}

disable_check_user()
{
	name=$1
	uid=$2
	primary=$3
	reserved_identity user "$name" "$uid"
	case $primary in
		root|wheel|spokes) die "disable refused: primary group $primary of $name is a reserved foundation group" ;;
	esac
	existing=$(passwd_entry "$name")
	[ -n "$existing" ] || return 0
	[ "$(field 3 "$existing")" = "$uid" ] ||
		die "disable refused: user $name exists with different UID (not the declared $uid)"
	want_gid=$(frag_gid "$primary")
	if [ -z "$want_gid" ]; then
		want_gid=$(group_gid "$primary")
		[ -n "$want_gid" ] ||
			die "disable refused: primary group $primary of $name is neither declared nor present"
	fi
	[ "$(field 4 "$existing")" = "$want_gid" ] ||
		die "disable refused: user $name exists with different primary group"
}

disable_check_group()
{
	name=$1
	gid=$2
	reserved_identity group "$name" "$gid"
	existing=$(group_entry "$name")
	[ -n "$existing" ] || return 0
	[ "$(field 3 "$existing")" = "$gid" ] ||
		die "disable refused: group $name exists with different GID (not the declared $gid)"
}

disable_validate()
{
	frag_groups=
	lineno=0
	while IFS= read -r line || [ -n "$line" ]; do
		lineno=$((lineno + 1))
		case $line in
			''|'#'*) continue ;;
		esac
		# shellcheck disable=SC2086
		set -- $line
		case $1 in
			group)
				[ $# -eq 3 ] || die "fragment line $lineno: group needs 2 fields"
				valid_name "$2" || die "invalid group name: $2"
				case $3 in
					''|*[!0-9]*) die "fragment line $lineno: invalid GID" ;;
				esac
				frag_groups="$frag_groups$2:$(($3 + 0)) "
				;;
			user)
				[ $# -eq 6 ] || die "fragment line $lineno: user needs 5 fields"
				valid_name "$2" || die "invalid user name: $2"
				valid_name "$4" || die "invalid primary group name: $4"
				case $3 in
					''|*[!0-9]*) die "fragment line $lineno: invalid UID" ;;
				esac
				;;
			dir) continue ;;
			*) die "fragment line $lineno: unknown stanza: $1" ;;
		esac
	done < "$FRAGMENT"
	lineno=0
	while IFS= read -r line || [ -n "$line" ]; do
		lineno=$((lineno + 1))
		case $line in
			''|'#'*) continue ;;
		esac
		# shellcheck disable=SC2086
		set -- $line
		case $1 in
			group) disable_check_group "$2" "$(($3 + 0))" ;;
			user) disable_check_user "$2" "$(($3 + 0))" "$4" ;;
		esac
	done < "$FRAGMENT"
}

sanitize_user()
{
	name=$1
	existing=$(passwd_entry "$name")
	if [ -z "$existing" ]; then
		log "user $name absent; nothing to disable"
		return 0
	fi
	# Apply-time backstop: even past validation, UID 0 and the
	# reserved names are never sanitized.
	case $name in
		root) die "disable refused: will not touch reserved identity $name" ;;
	esac
	[ "$(field 3 "$existing")" != 0 ] ||
		die "disable refused: will not touch UID 0"
	# Shadow: force field 2 locked, preserving every other field; a
	# missing row is created locked (same format as ensure).
	tmp=$(mktemp "$ROOT/etc/.saphira-sanitize.XXXXXX") ||
		die "cannot create sanitize workspace"
	if [ -n "$(shadow_entry "$name")" ]; then
		while IFS= read -r line || [ -n "$line" ]; do
			case $line in
				"$name":*)
					rest=${line#*:}
					rest=${rest#*:}
					printf '%s:!:%s\n' "$name" "$rest" >> "$tmp"
					;;
				*) printf '%s\n' "$line" >> "$tmp" ;;
			esac
		done < "$SHADOW"
		cat "$tmp" > "$SHADOW" || die "cannot lock shadow $name"
		log "shadow $name locked"
	else
		printf '%s:%s:0:0:99999:7:::\n' "$name" '!' >> "$SHADOW" ||
			die "cannot append shadow $name"
		log "shadow $name locked (was missing)"
	fi
	rm -f -- "$tmp"
	# Shell: force /sbin/nologin, preserving every other field.
	if [ "$(field 7 "$existing")" != /sbin/nologin ]; then
		tmp=$(mktemp "$ROOT/etc/.saphira-sanitize.XXXXXX") ||
			die "cannot create sanitize workspace"
		while IFS= read -r line || [ -n "$line" ]; do
			case $line in
				"$name":*)
					printf '%s:%s:%s:%s:%s:%s:/sbin/nologin\n' \
						"$(field 1 "$line")" "$(field 2 "$line")" \
						"$(field 3 "$line")" "$(field 4 "$line")" \
						"$(field 5 "$line")" "$(field 6 "$line")" \
						>> "$tmp"
					;;
				*) printf '%s\n' "$line" >> "$tmp" ;;
			esac
		done < "$PASSWD"
		cat "$tmp" > "$PASSWD" || die "cannot set nologin shell for $name"
		rm -f -- "$tmp"
		log "user $name shell set to /sbin/nologin"
	else
		log "user $name already nologin"
	fi
}

disable_apply()
{
	lineno=0
	while IFS= read -r line || [ -n "$line" ]; do
		lineno=$((lineno + 1))
		case $line in
			''|'#'*) continue ;;
		esac
		# shellcheck disable=SC2086
		set -- $line
		case $1 in
			group)
				if [ -n "$(group_entry "$2")" ]; then
					log "group $2 retained"
				else
					log "group $2 absent; not created"
				fi
				;;
			user) sanitize_user "$2" ;;
			dir) continue ;;
		esac
	done < "$FRAGMENT"
}

if [ "$MODE" = disable ]; then
	disable_validate
	disable_apply
	log "disable complete: $FRAGMENT"
	trap - EXIT HUP INT TERM
	unlock
	exit 0
fi

# Reserved declarations are never valid in any context (unlike
# UID/GID conflicts, which need database state to judge), so they
# are rejected here before the group pre-pass below can create
# anything. Malformed stanzas are skipped: the main passes produce
# the precise shape errors for those.
reject_reserved()
{
	lineno=0
	while IFS= read -r line || [ -n "$line" ]; do
		lineno=$((lineno + 1))
		case $line in
			''|'#'*) continue ;;
		esac
		# shellcheck disable=SC2086
		set -- $line
		case $1 in
			group)
				[ $# -eq 3 ] || continue
				valid_name "$2" || continue
				case $3 in
					''|*[!0-9]*) continue ;;
				esac
				reserved_identity group "$2" "$(($3 + 0))"
				;;
			user)
				[ $# -eq 6 ] || continue
				valid_name "$2" || continue
				case $3 in
					''|*[!0-9]*) continue ;;
				esac
				reserved_identity user "$2" "$(($3 + 0))"
				case $4 in
					root|wheel|spokes) die "refusing user $2: primary group $4 is a reserved foundation group" ;;
				esac
				;;
		esac
	done < "$FRAGMENT"
}
reject_reserved

lineno=0
# Pre-pass: groups first, so user stanzas may reference a primary group
# declared anywhere in the fragment regardless of line order.
while IFS= read -r line || [ -n "$line" ]; do
	lineno=$((lineno + 1))
	case $line in
		''|'#'*) continue ;;
	esac
	# shellcheck disable=SC2086
	set -- $line
	case $1 in
		group)
			[ $# -eq 3 ] || die "fragment line $lineno: group needs 2 fields"
			ensure_group "$2" "$3"
			;;
	esac
done < "$FRAGMENT"
lineno=0
while IFS= read -r line || [ -n "$line" ]; do
	lineno=$((lineno + 1))
	case $line in
		''|'#'*) continue ;;
	esac
	# shellcheck disable=SC2086
	set -- $line
	case $1 in
		group)
			[ $# -eq 3 ] || die "fragment line $lineno: group needs 2 fields"
			ensure_group "$2" "$3"
			;;
		user)
			[ $# -eq 6 ] || die "fragment line $lineno: user needs 5 fields"
			ensure_user "$2" "$3" "$4" "$5" "$6"
			;;
		dir)
			[ $# -eq 5 ] || die "fragment line $lineno: dir needs 4 fields"
			case $2 in
				/*) ;;
				*) die "fragment line $lineno: dir path must be absolute" ;;
			esac
			case $3 in
				0*|[1-7][0-7][0-7]|[1-7][0-7][0-7][0-7]) ;;
				*) die "fragment line $lineno: invalid mode: $3" ;;
			esac
			ensure_leaf "$2" "$3" "$4" "$5"
			;;
		*)
			die "fragment line $lineno: unknown stanza: $1"
			;;
	esac
done < "$FRAGMENT"
log "reconciliation complete: $FRAGMENT"
