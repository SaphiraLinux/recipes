#!/bin/sh
# ensure-identity.sh [--disable|--check] FRAGMENT — additive, idempotent
# system-identity reconciler, plus its removal counterpart.
#
# --check reports drift without changing anything (exit 1 on drift,
# exit 2 when the fragment could not be assessed at all).
# Both ensure and check honour administrator overrides from
# /etc/saphira/permissions/override.d for dir/file stanzas.
#
# Called ONLY from makepkg-generated package scripts, with the
# package's own accounts.d fragment. Ensure mode (post-install,
# post-upgrade) makes sure every declared group, user, locked shadow
# entry, and state directory exists. A present identity that exactly
# matches a declared legacy entry is migrated in place to its
# canonical IDs first (database rows only, with backup - the same
# semantics as saphira-identity reconcile --apply, so apk fix and apk
# upgrade self-heal recognised drift with no manual step); anything
# else already present is never modified, reordered, or rehashed.
#
# Disable mode (--disable, post-deinstall) sanitizes WITHOUT deleting:
# a removed package must never leave its historical service account
# usable for login. For every declared user that still matches its
# declaration it forces the shadow entry locked ('!') and the shell to
# /sbin/nologin, preserving UID, GID, home, and every other field;
# groups stay present and reserved; state directories are untouched
# (never walked, never chowned, never removed); fixed IDs are never
# recycled. Anything already absent is a silent no-op, so repeats are
# harmless. A declared name that exists with DIFFERENT UID/GID (or an
# unverifiable primary group) is FOREIGN: reality no longer matches
# the declaration, so removal has lost authority over that identity.
# Disable warns, leaves it byte-untouched, and succeeds - APK removal
# must never be blocked by declaration drift, and deinstall never
# renumbers anything. Reserved identities stay fatal in both modes:
# root/UID 0 and the foundation groups are refused always, before
# any write.
#
# Fragment syntax (strict; anything else fails closed):
#   group <name> <gid>
#   user <name> <uid> <primary-group> <home> <shell>
#   dir <path> <mode> <owner> <group>
#   file <path> <mode> <owner> <group>
# Blank lines and '#' comments are ignored.
#
# A legacy sidecar (<fragment>.legacy, same directory) records
# recognised history for the declared identities:
#   legacy user <name> <old-uid> <old-gid>
#   legacy group <name> <old-gid>
# When ensure meets a present identity whose UID/GID exactly matches
# a legacy entry, it migrates the database rows to the canonical IDs
# automatically (passwd fields 3/4, group field 3, gshadow field 3
# when that row exists; shadow rows are name-keyed and untouched),
# under the account lock with a timestamped backup, then verifies
# the canonical state through the normal path. The sidecar is the
# standing authorization: only declared pasts ever migrate.
# Anything not matching a legacy entry is an ordinary conflict and
# stays fatal, as do reserved identities and occupied targets.
# Disable mode never consults the sidecar. Repairs are per-entry, so
# a refusal after a partial repair leaves a backup and a clear
# error; re-running converges the repaired entries and retries the
# rest. Reconciliation of undeclared states still lives in
# saphira-identity(8): account-database records only, never
# filesystem ownership.
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
# - file reconciliation fixes ownership and mode on files the package
#   itself ships, never creates content: a missing path is a packaging
#   bug and fails closed, symlinks are refused (chown would follow the
#   link onto another package's target), and directories belong to the
#   dir stanza. Regular files and live-created fifos are accepted;
#   anything else special is refused. (Packaging itself cannot ship
#   fifos - APK payloads carry regular files only - so runtime fifos
#   such as qmail's queue trigger are created with ownership by the
#   service start_pre instead.) Owner/group references resolve to declared-or-present
#   identities; root and UID/GID 0 are built-ins needing no declaration.
#   Bare numbers besides 0 are refused so every other reference stays a
#   converge-checkable name. Like dirs, files are untouched by disable
#   mode (never walked, never chowned, never removed).
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
BACKUP_BASE=$ROOT/var/lib/saphira/identity-backups

log()
{
	printf 'ensure-identity: %s\n' "$*"
}

die()
{
	printf 'ensure-identity: ERROR: %s\n' "$*" >&2
	if [ "${CHECK:-0}" -eq 1 ]; then exit 2; else exit 1; fi
}

MODE=ensure
CHECK=0
case ${1:-} in
	--disable) MODE=disable; shift ;;
	--check) MODE=ensure; CHECK=1; shift ;;
	-*) die "usage: ensure-identity.sh [--disable|--check] FRAGMENT" ;;
esac
FRAGMENT=${1:?usage: ensure-identity.sh [--disable|--check] FRAGMENT}

DRIFT=0
CHECK_DONE=
drift()
{
	DRIFT=$((DRIFT + 1))
	printf 'ensure-identity: drift: %s\n' "$*"
}

test -f "$FRAGMENT" || die "fragment is missing: $FRAGMENT"
for f in "$PASSWD" "$GROUPF" "$SHADOW"; do
	test -f "$f" || die "account database is missing: $f"
done

# Administrator overrides (shared helper with ensure-fhs/ensure-caps/
# ensure-permissions). Validated on converge paths only (ensure and
# check): removal sanitizes identities and never converges paths, so
# --disable stays override-free and unsurprising.
if [ "$MODE" = ensure ]; then
	OVERRIDE_DIR=$ROOT/etc/saphira/permissions/override.d
	helper_dir=$(dirname -- "$0")
	if [ -f "$helper_dir/permissions-override.sh" ]; then
		# shellcheck disable=SC1091
		. "$helper_dir/permissions-override.sh"
	elif [ -f /usr/libexec/saphira/permissions-override.sh ]; then
		# shellcheck disable=SC1091
		. /usr/libexec/saphira/permissions-override.sh
	else
		die "permissions-override.sh is missing (reinstall saphira-baselayout)"
	fi
	ovr_init
fi

# Mode hygiene: the databases must be world-readable except shadow,
# regardless of the umask that created them (Hatched 2026-09 arrived
# with /etc/group mode 600 from an image build under a strict umask,
# breaking every non-root group lookup). Normalize on every run - this
# heals existing systems the next time any fragment installs, and makes
# fresh creation umask-independent. Content promises below are
# unaffected: modes are not entries. Check mode reports instead of
# healing: auditing must never mutate.
if [ "$CHECK" -eq 1 ]; then
	[ "$(stat -c '%a' "$PASSWD")" = 644 ] || drift "database $PASSWD mode is $(stat -c '%a' "$PASSWD") (want 644)"
	[ "$(stat -c '%a' "$GROUPF")" = 644 ] || drift "database $GROUPF mode is $(stat -c '%a' "$GROUPF") (want 644)"
	[ "$(stat -c '%a' "$SHADOW")" = 600 ] || drift "database $SHADOW mode is $(stat -c '%a' "$SHADOW") (want 600)"
else
	chmod 0644 "$PASSWD" "$GROUPF" || die "cannot set database modes"
	chmod 0600 "$SHADOW" || die "cannot set shadow mode"
fi

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
		if [ "$(field 3 "$existing")" != "$gid" ]; then
			if legacy_group_match "$name" "$(field 3 "$existing")"; then
				if [ "$CHECK" -eq 1 ]; then
					drift "group $name would migrate to GID $gid (legacy $(field 3 "$existing"))"
					return 0
				fi
				repair_group_legacy "$name" "$gid"
				existing=$(group_entry "$name")
			elif [ "$CHECK" -eq 1 ]; then
				drift "group conflict: $name exists with GID $(field 3 "$existing") (want $gid)"
				return 0
			fi
			[ "$(field 3 "$existing")" = "$gid" ] ||
				die "group conflict: $name exists with different GID"
		fi
		log "group $name ($gid) already present"
		return 0
	fi
	# Packaged range only on creation: 888..999 belong to local user
	# services and 1000+ to humans, so this tool never mints IDs there
	# (converging with an already-present entry above is fine and is
	# handled by the early return). A hand-provisioned local account
	# (e.g. qmail's fixed IDs) with matching attributes converges
	# silently instead of blocking the install.
	if [ "$gid" -ge 0 ] && [ "$gid" -le 887 ]; then
		:
	elif [ "$CHECK" -eq 1 ]; then
		drift "group $name ($gid) is outside the packaged range 0..887"
		return 0
	else
		die "GID outside packaged range 0..887: $gid"
	fi
	owner=$(gid_taken "$gid")
	if [ -n "$owner" ]; then
		if [ "$CHECK" -eq 1 ]; then
			drift "GID conflict: $gid already owned by group $owner (want $name)"
			return 0
		fi
		die "GID conflict: $gid already owned by group $owner"
	fi
	if [ "$CHECK" -eq 1 ]; then
		case $CHECK_DONE in
		*" g:$name "*) return 0 ;;
		esac
		CHECK_DONE="$CHECK_DONE g:$name "
		drift "group $name ($gid) would be created"
		return 0
	fi
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
		if [ "$(field 3 "$existing")" != "$uid" ] ||
			[ "$(field 4 "$existing")" != "$primary_gid" ]; then
			if legacy_user_match "$name" "$(field 3 "$existing")" "$(field 4 "$existing")"; then
				if [ "$CHECK" -eq 1 ]; then
					drift "user $name would migrate to UID $uid (legacy $(field 3 "$existing"))"
					return 0
				fi
				repair_user_legacy "$name" "$uid" "$primary_gid" "$primary"
				existing=$(passwd_entry "$name")
			elif [ "$CHECK" -eq 1 ]; then
				drift "user conflict: $name exists with UID $(field 3 "$existing") (want $uid)"
				return 0
			fi
			[ "$(field 3 "$existing")" = "$uid" ] ||
				die "user conflict: $name exists with different UID"
			[ "$(field 4 "$existing")" = "$primary_gid" ] ||
				die "user conflict: $name exists with different primary group"
		fi
		log "user $name ($uid) already present"
		ensure_shadow "$name"
		ensure_home "$home" "$uid" "$primary"
		return 0
	fi
	# Packaged range only on creation (see ensure_group): a locally
	# hand-provisioned account with matching attributes converges
	# above via the early return and never reaches this refusal.
	if [ "$uid" -ge 0 ] && [ "$uid" -le 887 ]; then
		:
	elif [ "$CHECK" -eq 1 ]; then
		drift "user $name ($uid) is outside the packaged range 0..887"
		return 0
	else
		die "UID outside packaged range 0..887: $uid"
	fi
	owner=$(uid_taken "$uid")
	if [ -n "$owner" ]; then
		if [ "$CHECK" -eq 1 ]; then
			drift "UID conflict: $uid already owned by user $owner (want $name)"
			return 0
		fi
		die "UID conflict: $uid already owned by user $owner"
	fi
	# primary group: fragment-declared, already present, or base-seeded.
	if [ -z "$(group_entry "$primary")" ]; then
		tsv_gid=$(tsv_group_gid "$primary") || tsv_gid=
		if [ -n "$tsv_gid" ]; then
			ensure_group "$primary" "$tsv_gid"
		elif [ "$CHECK" -eq 1 ]; then
			# Check mode only: a primary the pre-pass already
			# reported as would-be-created satisfies resolution
			# for reporting (the user drift is recorded below).
			# A primary nobody declares is still a hard error.
			case $CHECK_DONE in
			*" g:$primary "*) ;;
			*) die "primary group is not declared, present, or base-seeded: $primary" ;;
			esac
		else
			die "primary group is not declared, present, or base-seeded: $primary"
		fi
	fi
	if [ "$CHECK" -eq 1 ]; then
		case $CHECK_DONE in
		*" u:$name "*) return 0 ;;
		esac
		CHECK_DONE="$CHECK_DONE u:$name "
		drift "user $name ($uid) would be created (shadow locked, home $home)"
		return 0
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
			*)
				if [ "$CHECK" -eq 1 ]; then
					drift "shadow $name has a usable password hash"
				else
					die "shadow $name has a usable password hash; refusing to touch credentials"
				fi
				;;
		esac
		return 0
	fi
	if [ "$CHECK" -eq 1 ]; then
		drift "shadow $name would be created locked"
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
	# Administrator override: ignore skips the leaf, pin
	# substitutes its declared values (same helper as
	# ensure-fhs/ensure-caps/ensure-permissions).
	eff=$(ovr_lookup "$path")
	case $eff in
	ignore)
		log "directory $path skipped (administrator override)"
		return 0
		;;
	pin\|*)
		rest=${eff#pin|}
		owner=${rest%%|*}
		rest=${rest#*|}
		group=${rest%%|*}
		rest=${rest#*|}
		mode=${rest%%|*}
		log "directory $path pinned by administrator override ($owner:$group $mode)"
		;;
	esac
	# create missing leading components with default modes; only the
	# leaf receives declared mode/ownership, and only when different.
	parent=$(dirname -- "$path")
	if [ ! -d "$ROOT$parent" ]; then
		if [ "$CHECK" -eq 1 ]; then
			drift "directory parents of $path would be created"
		else
			mkdir -p "$ROOT$parent" || die "cannot create $parent"
		fi
	fi
	if [ ! -e "$ROOT$path" ] && [ ! -L "$ROOT$path" ]; then
		if [ "$CHECK" -eq 1 ]; then
			drift "directory $path would be created ($owner:$group $mode)"
			return 0
		fi
		mkdir "$ROOT$path" || die "cannot create $path"
		log "directory $path created"
	fi
	[ -d "$ROOT$path" ] || {
		if [ "$CHECK" -eq 1 ]; then
			drift "not a directory: $path"
			return 0
		fi
		die "not a directory: $path"
	}
	current_mode=$(stat -c '%a' "$ROOT$path") || die "cannot stat $path"
	current_owner=$(stat -c '%u:%g' "$ROOT$path") || die "cannot stat $path"
	want_owner=$(id_numeric "$owner"); want_group=$(id_numeric_group "$group")
	[ -n "$want_owner" ] || die "unknown owner: $owner"
	[ -n "$want_group" ] || die "unknown group: $group"
	if [ "$current_owner" != "$want_owner:$want_group" ]; then
		if [ "$CHECK" -eq 1 ]; then
			drift "directory $path ownership is $current_owner (want $want_owner:$want_group)"
		else
			chown "$want_owner:$want_group" "$ROOT$path" ||
				die "cannot set ownership on $path"
			log "directory $path ownership set to $want_owner:$want_group"
		fi
	fi
	# normalize declared mode (accept 755 or 0755) for comparison
	want_mode=$mode
	while [ "$want_mode" != "${want_mode#0}" ]; do
		want_mode=${want_mode#0}
	done
	[ -n "$want_mode" ] || want_mode=0
	if [ "$current_mode" != "$want_mode" ]; then
		if [ "$CHECK" -eq 1 ]; then
			drift "directory $path mode is $current_mode (want $mode)"
		else
			chmod "$mode" "$ROOT$path" || die "cannot set mode on $path"
			log "directory $path mode set to $mode"
		fi
	fi
}

id_numeric()
{
	# Prints the numeric UID (possibly empty when unknown; the
	# caller fails closed on empty). Always exits 0: a nonzero
	# return inside $() under set -eu would kill the helper before
	# the caller can report WHICH reference is unknown.
	case $1 in
		''|*[!0-9]*)
			found=$(field 3 "$(passwd_entry "$1")")
			if [ -n "$found" ]; then printf '%s' "$found"; return 0; fi
			if [ "$CHECK" -eq 1 ]; then check_declared_id u "$1"; return 0; fi
			return 0
			;;
		*) printf '%s' "$1" ;;
	esac
}

id_numeric_group()
{
	case $1 in
		''|*[!0-9]*)
			found=$(group_gid "$1")
			if [ -n "$found" ]; then printf '%s' "$found"; return 0; fi
			if [ "$CHECK" -eq 1 ]; then check_declared_id g "$1"; return 0; fi
			return 0
			;;
		*) printf '%s' "$1" ;;
	esac
}

# --- check-mode fragment identity index ---
#
# In --check mode, declared-but-absent identities must still resolve
# for drift reporting: nothing is created, so the live databases
# cannot answer for them. The fragment is indexed once (well-formed
# user/group stanzas only; malformed lines still die in the main
# passes) and consulted as a fallback. Apply mode never consults
# it (creation order guarantees live resolution there).
CHECK_INDEX=
CHECK_INDEXED=
check_index_fragment() {
	[ "$CHECK" -eq 1 ] || return 0
	[ -n "$CHECK_INDEXED" ] && return 0
	CHECK_INDEXED=1
	while IFS= read -r line || [ -n "$line" ]; do
		# shellcheck disable=SC2086
		set -- $line
		[ $# -eq 0 ] && continue
		case $1 in
		\#*) continue ;;
		esac
		case $1 in
		user)
			[ $# -eq 6 ] || continue
			valid_name "$2" || continue
			case $3 in
			''|*[!0-9]*) continue ;;
			esac
			CHECK_INDEX="$CHECK_INDEX u:$2:$3"
			;;
		group)
			[ $# -eq 3 ] || continue
			valid_name "$2" || continue
			case $3 in
			''|*[!0-9]*) continue ;;
			esac
			CHECK_INDEX="$CHECK_INDEX g:$2:$3"
			;;
		esac
	done <"$FRAGMENT"
}

check_declared_id() {
	# $1(u|g) $2(name): print the fragment-declared ID, or nothing.
	# Indexed names passed valid_name (plain identifiers, no glob
	# characters), so the expansion match is exact. The query name
	# is validated too: a malformed reference resolves to nothing
	# (the caller then fails closed, exactly like apply mode).
	valid_name "$2" || return 0
	case $CHECK_INDEX in
	*" $1:$2:"*)
		rest=${CHECK_INDEX##*" $1:$2:"}
		printf '%s' "${rest%% *}"
		;;
	esac
}

# --- legacy sidecar (<fragment>.legacy): recognised history ---
#
# Loaded once on the ensure path (disable never consults it).
# LEGACY_USERS holds "name:uid:gid" entries, LEGACY_GROUPS "name:gid".
# Legacy IDs are history, never creation targets: no range restriction
# applies, but reserved identities are refused outright (fail closed).
legacy_path=
legacy_users=
legacy_groups=

# --- legacy auto-repair (ensure path only) ---
#
# An exact sidecar match authorizes an in-place migration with the
# same safety rules as saphira-identity reconcile --apply: the live
# row must equal the declared past exactly, the canonical target
# must be free (or already self), reserved identities never qualify
# (refused at sidecar parse), and every mutation lands under the
# account lock this script already holds, behind a timestamped
# backup, with a post-write re-read. Live processes holding either
# ID are warned about, never fatal: the kernel keeps them on their
# numeric ID while the name row moves, and the operator restarts the
# affected service afterwards. gshadow rows migrate when present;
# shadow rows are name-keyed and untouched.
backup_done=
backup_dir=

ensure_backup()
{
	if [ -n "$backup_done" ]; then return 0; fi
	stamp=$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || date +%Y%m%dT%H%M%S)
	backup_dir=$BACKUP_BASE/$stamp
	mkdir -p "$backup_dir" || die "cannot create backup dir: $backup_dir"
	chmod 0700 "$backup_dir" || die "cannot secure backup dir"
	for bf in "$PASSWD" "$GROUPF" "$SHADOW"; do
		cp -p "$bf" "$backup_dir/" || die "cannot back up $bf"
	done
	if [ -f "$ROOT/etc/gshadow" ]; then
		cp -p "$ROOT/etc/gshadow" "$backup_dir/" || die "cannot back up gshadow"
	fi
	backup_done=1
	log "account databases backed up to $backup_dir"
}

rewrite_field()
{
	# rewrite_field FILE NAME FIELD NEWVAL - atomic rename, all
	# other bytes preserved; refuses malformed rows.
	file=$1
	name=$2
	nfield=$3
	newval=$4
	tmp=$(mktemp "$ROOT/etc/.saphira-ensure-repair.XXXXXX") ||
		die "cannot create repair workspace"
	while IFS= read -r line || [ -n "$line" ]; do
		case $line in
			"$name":*)
				rest=$line
				prefix=
				i=1
				while [ "$i" -lt "$nfield" ]; do
					prefix=$prefix${rest%%:*}:
					rest=${rest#*:}
					i=$((i + 1))
				done
				tail=${rest#*:}
				case $rest in
					*:*) ;;
					*) die "refusing to rewrite malformed row for $name in $file" ;;
				esac
				printf '%s%s:%s\n' "$prefix" "$newval" "$tail" >> "$tmp"
				;;
			*) printf '%s\n' "$line" >> "$tmp" ;;
		esac
	done < "$file"
	mv -f "$tmp" "$file" || die "cannot install rewritten $file"
}

line_holds()
{
	# line_holds KIND LINE OLD NEW - status check in a subshell so
	# the field split cannot clobber the caller's positionals.
	(
		kind=$1
		line=$2
		old=$3
		new=$4
		set -f
		# shellcheck disable=SC2086
		set -- $line
		case $kind in
			uid) [ "$1" = Uid: ] || exit 1 ;;
			gid) [ "$1" = Gid: ] || exit 1 ;;
		esac
		shift
		for v in "$@"; do
			if [ "$v" = "$old" ] || [ "$v" = "$new" ]; then exit 0; fi
		done
		exit 1
	)
}

warn_procs()
{
	kind=$1
	old=$2
	new=$3
	[ -d "$ROOT/proc" ] || return 0
	for status in "$ROOT"/proc/[0-9]*/status; do
		[ -f "$status" ] || continue
		while IFS= read -r line || [ -n "$line" ]; do
			case $line in
				Uid:*|Gid:*)
					if line_holds "$kind" "$line" "$old" "$new"; then
						pid=${status%/status}
						log "WARNING: live process ${pid##*/} holds $kind $old/$new; restart affected services after repair"
					fi
					break
					;;
			esac
		done < "$status" 2>/dev/null || true
	done
}

repair_group_legacy()
{
	name=$1
	ngid=$2
	owner=$(gid_taken "$ngid")
	if [ -n "$owner" ] && [ "$owner" != "$name" ]; then
		die "legacy repair refused: target GID $ngid already owned by group $owner"
	fi
	warn_procs gid "$(field 3 "$(group_entry "$name")")" "$ngid"
	ensure_backup
	rewrite_field "$GROUPF" "$name" 3 "$ngid"
	if [ -f "$ROOT/etc/gshadow" ] && [ -n "$(find_line "$ROOT/etc/gshadow" "$name" || true)" ]; then
		rewrite_field "$ROOT/etc/gshadow" "$name" 3 "$ngid"
	fi
	[ "$(field 3 "$(group_entry "$name")")" = "$ngid" ] ||
		die "legacy repair post-verify failed for group $name - restore from $backup_dir"
	log "group $name migrated from legacy to GID $ngid (backup at $backup_dir)"
}

repair_user_legacy()
{
	name=$1
	nuid=$2
	ngid=$3
	primary=$4
	owner=$(uid_taken "$nuid")
	if [ -n "$owner" ] && [ "$owner" != "$name" ]; then
		die "legacy repair refused: target UID $nuid already owned by user $owner"
	fi
	# The canonical primary row exists by now (groups reconcile in
	# the pre-pass): the target GID must be owned by the declared
	# primary group itself. Anything else - missing row, stranger
	# owner - stays fatal.
	gowner=$(gid_taken "$ngid")
	if [ "$gowner" != "$primary" ]; then
		die "legacy repair refused: target primary GID $ngid is not owned by group $primary (held by ${gowner:-nobody})"
	fi
	warn_procs uid "$(field 3 "$(passwd_entry "$name")")" "$nuid"
	ensure_backup
	rewrite_field "$PASSWD" "$name" 3 "$nuid"
	rewrite_field "$PASSWD" "$name" 4 "$ngid"
	[ "$(field 3 "$(passwd_entry "$name")")" = "$nuid" ] &&
		[ "$(field 4 "$(passwd_entry "$name")")" = "$ngid" ] ||
		die "legacy repair post-verify failed for user $name - restore from $backup_dir"
	log "user $name migrated from legacy to $nuid:$ngid (backup at $backup_dir)"
}

legacy_user_match()
{
	# legacy_user_match NAME UID GID - true on exact triple match.
	case " $legacy_users " in
		*" $1:$2:$3 "*) return 0 ;;
	esac
	return 1
}

legacy_group_match()
{
	case " $legacy_groups " in
		*" $1:$2 "*) return 0 ;;
	esac
	return 1
}

load_legacy()
{
	legacy_path=$FRAGMENT.legacy
	legacy_users=
	legacy_groups=
	[ -f "$legacy_path" ] || return 0
	lineno=0
	while IFS= read -r line || [ -n "$line" ]; do
		lineno=$((lineno + 1))
		case $line in
			''|'#'*) continue ;;
		esac
		# shellcheck disable=SC2086
		set -- $line
		[ "$1" = legacy ] || die "legacy line $lineno: unknown stanza: $1"
		case $2 in
			user)
				[ $# -eq 5 ] || die "legacy line $lineno: legacy user needs 3 fields"
				valid_name "$3" || die "legacy line $lineno: invalid user name: $3"
				case $4 in
					''|*[!0-9]*) die "legacy line $lineno: invalid UID" ;;
				esac
				case $5 in
					''|*[!0-9]*) die "legacy line $lineno: invalid GID" ;;
				esac
				case $3 in
					root) die "legacy line $lineno: root is never a legacy identity" ;;
				esac
				case $4 in
					0) die "legacy line $lineno: UID 0 is never a legacy identity" ;;
				esac
				legacy_users="$legacy_users$3:$(($4 + 0)):$(($5 + 0)) "
				;;
			group)
				[ $# -eq 4 ] || die "legacy line $lineno: legacy group needs 2 fields"
				valid_name "$3" || die "legacy line $lineno: invalid group name: $3"
				case $4 in
					''|*[!0-9]*) die "legacy line $lineno: invalid GID" ;;
				esac
				case $3 in
					root|wheel|spokes) die "legacy line $lineno: $3 is never a legacy identity" ;;
				esac
				case $4 in
					0|1|2) die "legacy line $lineno: GID $4 is never a legacy identity" ;;
				esac
				legacy_groups="$legacy_groups$3:$(($4 + 0)) "
				;;
			*)
				die "legacy line $lineno: unknown legacy kind: $2" ;;
		esac
	done < "$legacy_path"
}

file_owner_numeric()
{
	# root/UID 0 are built-ins (no declaration needed); every other
	# reference must resolve to a passwd entry, which exists by the
	# time the file pass runs for declared identities. Bare numbers
	# besides 0 are refused so references stay converge-checkable
	# names (an empty print means unknown; the caller dies). In
	# check mode the fragment index answers for declared-but-absent
	# identities (nothing is created to resolve live).
	case $1 in
		0) printf '0' ;;
		''|*[!0-9]*)
			found=$(field 3 "$(passwd_entry "$1")")
			if [ -n "$found" ]; then printf '%s' "$found"; return 0; fi
			if [ "$CHECK" -eq 1 ]; then check_declared_id u "$1"; return 0; fi
			return 0
			;;
		*) die "numeric file owner refs forbidden except 0: $1 (use the identity name)" ;;
	esac
}

file_group_numeric()
{
	case $1 in
		0) printf '0' ;;
		''|*[!0-9]*)
			found=$(group_gid "$1")
			if [ -n "$found" ]; then printf '%s' "$found"; return 0; fi
			if [ "$CHECK" -eq 1 ]; then check_declared_id g "$1"; return 0; fi
			return 0
			;;
		*) die "numeric file group refs forbidden except 0: $1 (use the identity name)" ;;
	esac
}

ensure_file()
{
	path=$1
	mode=$2
	owner=$3
	group=$4
	# Administrator override (same helper as the leaf above).
	eff=$(ovr_lookup "$path")
	case $eff in
	ignore)
		log "file $path skipped (administrator override)"
		return 0
		;;
	pin\|*)
		rest=${eff#pin|}
		owner=${rest%%|*}
		rest=${rest#*|}
		group=${rest%%|*}
		rest=${rest#*|}
		mode=${rest%%|*}
		log "file $path pinned by administrator override ($owner:$group $mode)"
		;;
	esac
	[ -L "$ROOT$path" ] &&
		die "not a regular file: $path (refusing to follow symlinks)"
	[ -d "$ROOT$path" ] &&
		die "not a file: $path (directories use the dir stanza)"
	# Regular files and fifos (qmail's queue trigger) take ownership;
	# anything else special is refused.
	if [ ! -f "$ROOT$path" ] && [ ! -p "$ROOT$path" ]; then
		if [ "$CHECK" -eq 1 ]; then
			drift "file stanza target is missing: $path"
			return 0
		fi
		die "file stanza target is missing: $path (files must ship in the package payload)"
	fi
	want_owner=$(file_owner_numeric "$owner")
	want_group=$(file_group_numeric "$group")
	[ -n "$want_owner" ] || die "unknown owner: $owner"
	[ -n "$want_group" ] || die "unknown group: $group"
	current_owner=$(stat -c '%u:%g' "$ROOT$path") || die "cannot stat $path"
	if [ "$current_owner" != "$want_owner:$want_group" ]; then
		if [ "$CHECK" -eq 1 ]; then
			drift "file $path ownership is $current_owner (want $want_owner:$want_group)"
		else
			chown "$want_owner:$want_group" "$ROOT$path" ||
				die "cannot set ownership on $path"
			log "file $path ownership set to $want_owner:$want_group"
		fi
	fi
	# normalize declared mode (accept 755 or 0755, keep setuid bits)
	# for comparison
	want_mode=$mode
	while [ "$want_mode" != "${want_mode#0}" ]; do
		want_mode=${want_mode#0}
	done
	[ -n "$want_mode" ] || want_mode=0
	current_mode=$(stat -c '%a' "$ROOT$path") || die "cannot stat $path"
	if [ "$current_mode" != "$want_mode" ]; then
		if [ "$CHECK" -eq 1 ]; then
			drift "file $path mode is $current_mode (want $mode)"
		else
			chmod "$mode" "$ROOT$path" || die "cannot set mode on $path"
			log "file $path mode set to $mode"
		fi
	fi
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
# Mismatches do not refuse: the identity is recorded foreign (warned,
# retained, skipped). Phase 2 (disable_apply) forces locked shadow +
# nologin shell on verified identities only, retains groups, and
# ignores state entirely.
frag_groups=
foreign_users=
foreign_groups=

is_foreign()
{
	# is_foreign KIND NAME - true when validation recorded NAME as
	# a foreign identity of that kind. Names cannot contain spaces
	# (valid_name), so space-separated lists are exact.
	case $1 in
		user) case " $foreign_users " in *" $2 "*) return 0 ;; esac ;;
		group) case " $foreign_groups " in *" $2 "*) return 0 ;; esac ;;
	esac
	return 1
}

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
	if [ "$(field 3 "$existing")" != "$uid" ]; then
		log "WARNING: user $name UID differs from declared $uid; foreign identity retained unchanged"
		foreign_users="$foreign_users $name"
		return 0
	fi
	want_gid=$(frag_gid "$primary")
	if [ -z "$want_gid" ]; then
		want_gid=$(group_gid "$primary")
		if [ -z "$want_gid" ]; then
			log "WARNING: primary group $primary of $name is neither declared nor present; foreign identity retained unchanged"
			foreign_users="$foreign_users $name"
			return 0
		fi
	fi
	if [ "$(field 4 "$existing")" != "$want_gid" ]; then
		log "WARNING: user $name primary group differs from declared $primary; foreign identity retained unchanged"
		foreign_users="$foreign_users $name"
		return 0
	fi
}

disable_check_group()
{
	name=$1
	gid=$2
	reserved_identity group "$name" "$gid"
	existing=$(group_entry "$name")
	[ -n "$existing" ] || return 0
	if [ "$(field 3 "$existing")" != "$gid" ]; then
		log "WARNING: group $name GID differs from declared $gid; foreign identity retained unchanged"
		foreign_groups="$foreign_groups $name"
	fi
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
			# Files are state, and state is untouched by disable mode:
			# shape-checked here so malformed stanzas still fail
			# closed, then skipped by both passes below.
			file)
				[ $# -eq 5 ] || die "fragment line $lineno: file needs 4 fields"
				;;
		# The sysusers stanza selects the caller's native mechanism
		# (the generated caller runs systemd-sysusers after the
		# reconciler): it declares no user/group/dir/file, so the
		# helper skips it in every pass. Arity enforced so malformed
		# fragments still fail closed.
		sysusers)
			[ $# -eq 1 ] || die "fragment line $lineno: sysusers takes no fields"
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
	if is_foreign user "$name"; then
		log "user $name is foreign; left untouched"
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
load_legacy
check_index_fragment

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
		# File stanzas are deferred to the post-pass below: owners
		# must resolve after every user/group stanza has applied,
		# regardless of line order.
		file)
			continue
			;;
		# The sysusers stanza selects the caller's native mechanism
		# (the generated caller runs systemd-sysusers after the
		# reconciler): it declares no user/group/dir/file, so the
		# helper skips it in every pass. Arity enforced so malformed
		# fragments still fail closed.
		sysusers)
			[ $# -eq 1 ] || die "fragment line $lineno: sysusers takes no fields"
			;;
		*)
			die "fragment line $lineno: unknown stanza: $1"
			;;
	esac
done < "$FRAGMENT"
# Post-pass: files last, so owner/group references resolve against the
# fully reconciled user/group set (declared, present, or root/0).
lineno=0
while IFS= read -r line || [ -n "$line" ]; do
	lineno=$((lineno + 1))
	case $line in
		''|'#'*) continue ;;
	esac
	# shellcheck disable=SC2086
	set -- $line
	case $1 in
		file)
			[ $# -eq 5 ] || die "fragment line $lineno: file needs 4 fields"
			case $2 in
				/*) ;;
				*) die "fragment line $lineno: file path must be absolute" ;;
			esac
			case $2 in
				*'..'*) die "fragment line $lineno: file path must be normalized (no ..)" ;;
			esac
			case $3 in
				0*|[1-7][0-7][0-7]|[1-7][0-7][0-7][0-7]) ;;
				*) die "fragment line $lineno: invalid mode: $3" ;;
			esac
			ensure_file "$2" "$3" "$4" "$5"
			;;
	esac
	done < "$FRAGMENT"
if [ "$CHECK" -eq 1 ]; then
	if [ "$DRIFT" -eq 0 ]; then
		log "check: $FRAGMENT clean"
		exit 0
	fi
	log "check: $FRAGMENT: $DRIFT drift(s)"
	exit 1
fi
log "reconciliation complete: $FRAGMENT"
