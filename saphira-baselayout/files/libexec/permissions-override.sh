#!/bin/sh
# permissions-override.sh — administrator override lookup, shared by the
# Saphira reconciliation tools (ensure-identity.sh, ensure-fhs,
# ensure-caps, ensure-permissions). Sourced, never executed.
#
# Saphira-owned infrastructure (saphira-baselayout). No dependency
# beyond POSIX sh: this helper must work in virgin seed roots.
#
# Override directory: $OVERRIDE_DIR (callers set it to
# $ROOT/etc/saphira/permissions/override.d; defaults to the live
# path). Package-owned declarations and administrator-owned
# overrides stay separate files: packages can never write here
# (nothing in a payload may populate it — makepkg refuses), and
# package upgrades never touch it (/etc is apk-protected).
#
# Grammar (strict; anything malformed fails closed):
#   ignore <abspath>
#   pin <abspath> <owner> <group> <mode>
#   pin-cap <abspath> <capspec>
# Blank lines and '#' comments are ignored.
#
# Semantics:
# - Overrides never ADD claims. A rule fires only for a path the
#   consuming tool already addresses from a package declaration (or,
#   for ensure-permissions --system, from the installed package
#   database). An override for an unclaimed path is silently inert
#   in per-package tools and a reported warning in --system: no
#   ordinary package can claim another package's path merely
#   because an override mechanism exists.
# - `ignore` skips convergence of that exact path (leaf only, never
#   recursive — same discipline as every declaration).
# - `pin` substitutes owner/group/mode for that exact path.
# - `pin-cap` substitutes the capability set for that exact path.
# - First matching file (sorted) wins; a second rule for the same
#   path and kind fails closed (ambiguous administrator intent is
#   never guessed at).
#
# API: ovr_init once, then per path:
#   ovr_lookup <abspath>      ownership axis: `ignore`,
#                             `pin|owner|group|mode`, or `none`
#                             (pin wins over ignore)
#   ovr_lookup_cap <abspath>  capability axis: `pincap|spec`
#                             or `none`
# The axes are independent: a pin never shadows a pin-cap and
# vice versa. All output is pipe-separated (paths may contain
# spaces). Callers must define die() first.
#
# Capability vocabulary (canonical sh-side list; makepkg carries the
# identical list in Python — the permissions suite asserts they
# match). Linux capability names, supporting flags e/p/i.
OVR_CAP_NAMES="cap_chown cap_dac_override cap_dac_read_search cap_fowner cap_fsetid cap_kill cap_setgid cap_setuid cap_setpcap cap_linux_immutable cap_net_bind_service cap_net_admin cap_net_raw cap_ipc_lock cap_ipc_owner cap_sys_module cap_sys_rawio cap_sys_chroot cap_sys_ptrace cap_sys_pacct cap_sys_admin cap_sys_boot cap_sys_nice cap_sys_resource cap_sys_time cap_sys_tty_config cap_mknod cap_lease cap_audit_write cap_audit_control cap_setfcap cap_mac_override cap_mac_admin cap_syslog cap_wake_alarm cap_block_suspend cap_audit_read cap_perfmon cap_bpf cap_checkpoint_restore"

OVR_RULES=
OVR_LOADED=

ovr_valid_abspath() {
	case $1 in
	/ | /*) ;;
	*) return 1 ;;
	esac
	case $1 in
	*//* | */ | *..*) return 1 ;;
	esac
	# Rule storage is `kind|path|...` matched by expansion: `|`
	# would corrupt fields, glob characters would corrupt matching,
	# and whitespace never survives stanza splitting anyway.
	case $1 in
	*\|* | *\** | *\?* | *\[*) return 1 ;;
	esac
	case $1 in
	*[[:space:]]*) return 1 ;;
	esac
	return 0
}

ovr_valid_name() {
	case $1 in
	root | 0) return 0 ;;
	*) expr "$1" : '[A-Za-z0-9_.][A-Za-z0-9_.-]*$' >/dev/null ;;
	esac
}

ovr_valid_mode() {
	case $1 in
	'' | *[!0-7]*) return 1 ;;
	esac
	stripped=$1
	while [ "${stripped#0}" != "$stripped" ]; do
		stripped=${stripped#0}
	done
	[ -n "$stripped" ] || stripped=0
	len=${#stripped}
	[ "$len" -ge 3 ] && [ "$len" -le 4 ] || return 1
	case $stripped in
	[1-7]*) return 0 ;;
	*) return 1 ;;
	esac
}

# ovr_valid_capspec $1: abspath-free capability spec validation.
# Form: <name>[,<name>...]<+|=>flags, e.g. cap_net_bind_service+ep.
# Names must be known Linux capabilities; flags 1-3 of e/p/i.
ovr_valid_capspec() {
	spec=$1
	case $spec in
	*[+=]*) ;;
	*) return 1 ;;
	esac
	names=${spec%%[+=]*}
	flags=${spec##*[+=]}
	case $flags in
	'' | *[!epi]* | ????*) return 1 ;;
	esac
	[ -n "$names" ] || return 1
	oldifs=$IFS
	IFS=,
	# shellcheck disable=SC2086
	set -- $names
	IFS=$oldifs
	[ $# -ge 1 ] || return 1
	for capname in "$@"; do
		hit=0
		for known in $OVR_CAP_NAMES; do
			if [ "$capname" = "$known" ]; then
				hit=1
				break
			fi
		done
		[ "$hit" -eq 1 ] || return 1
	done
	return 0
}

ovr_init() {
	[ -n "$OVR_LOADED" ] && return 0
	OVR_LOADED=1
	OVR_RULES=
	dir=${OVERRIDE_DIR:-/etc/saphira/permissions/override.d}
	[ -d "$dir" ] || return 0
	for conf in "$dir"/*.conf; do
		[ -f "$conf" ] || continue
		[ -L "$conf" ] && die "override file must not be a symlink: $conf"
		lineno=0
		while IFS= read -r raw || [ -n "$raw" ]; do
			lineno=$((lineno + 1))
			# shellcheck disable=SC2086
			set -- $raw
			[ $# -eq 0 ] && continue
			case $1 in
			\#*) continue ;;
			esac
			kind=$1
			case $kind in
			ignore)
				[ $# -eq 2 ] || die "$conf:$lineno: malformed ignore stanza"
				ovr_valid_abspath "$2" || die "$conf:$lineno: path must be absolute and normalized: $2"
				;;
			pin)
				[ $# -eq 5 ] || die "$conf:$lineno: malformed pin stanza"
				ovr_valid_abspath "$2" || die "$conf:$lineno: path must be absolute and normalized: $2"
				ovr_valid_name "$3" || die "$conf:$lineno: invalid owner name: $3"
				ovr_valid_name "$4" || die "$conf:$lineno: invalid group name: $4"
				ovr_valid_mode "$5" || die "$conf:$lineno: invalid mode: $5"
				;;
			pin-cap)
				[ $# -eq 3 ] || die "$conf:$lineno: malformed pin-cap stanza"
				ovr_valid_abspath "$2" || die "$conf:$lineno: path must be absolute and normalized: $2"
				ovr_valid_capspec "$3" || die "$conf:$lineno: invalid capability spec: $3"
				;;
			*)
				die "$conf:$lineno: malformed stanza"
				;;
			esac
			# Ambiguous administrator intent fails closed: one rule
			# per path per kind (ignore vs pin vs pin-cap are
			# distinct kinds and may coexist). Pure-expansion
			# match (no grep: this helper runs in virgin seed
			# roots); exact because every rule line is
			# `kind|path|...` and neither kind nor path may
			# contain `|`.
			case $OVR_RULES in
			*"$kind|$2|"*)
				die "$conf:$lineno: duplicate override for $2 ($kind already declared)"
				;;
			esac
			if [ -z "$OVR_RULES" ]; then
				OVR_RULES="$kind|$2|${3:-}|${4:-}|${5:-}"
			else
				OVR_RULES="$OVR_RULES
$kind|$2|${3:-}|${4:-}|${5:-}"
			fi
		done <"$conf"
	done
}

# ovr_lookup $1(abspath): ownership axis — prints one line:
# `ignore`, `pin|owner|group|mode`, or `none`. pin wins over
# ignore when both exist (an explicit value beats a skip).
ovr_lookup() {
	want=$1
	hit_ignore=0
	oldifs=$IFS
	IFS='
'
	for rule in $OVR_RULES; do
		IFS=$oldifs
		[ -n "$rule" ] || { IFS='
'; continue; }
		rkind=${rule%%|*}
		rest=${rule#*|}
		rpath=${rest%%|*}
		rest=${rest#*|}
		if [ "$rpath" = "$want" ]; then
			case $rkind in
			pin)
				printf 'pin|%s\n' "$rest"
				IFS=$oldifs
				return 0
				;;
			ignore)
				hit_ignore=1
				;;
			esac
		fi
		IFS='
'
	done
	IFS=$oldifs
	if [ "$hit_ignore" -eq 1 ]; then
		printf 'ignore\n'
	else
		printf 'none\n'
	fi
}

# ovr_lookup_cap $1(abspath): capability axis — prints
# `pincap|spec` or `none`.
ovr_lookup_cap() {
	want=$1
	oldifs=$IFS
	IFS='
'
	for rule in $OVR_RULES; do
		IFS=$oldifs
		[ -n "$rule" ] || { IFS='
'; continue; }
		rkind=${rule%%|*}
		rest=${rule#*|}
		rpath=${rest%%|*}
		rest=${rest#*|}
		if [ "$rpath" = "$want" ] && [ "$rkind" = "pin-cap" ]; then
			printf 'pincap|%s\n' "${rest%%|*}"
			IFS=$oldifs
			return 0
		fi
		IFS='
'
	done
	IFS=$oldifs
	printf 'none\n'
}
