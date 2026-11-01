#!/bin/sh
# minimal-systemd dependency closure: gcc-libs must not be reachable from
# the minimal systemd profile through any recipe-declared runtime edge.
#
# Incident: expat declared depends="gcc-libs", which installed an 8,389
# KiB compiler runtime library into every minimal systemd image via
# systemd -> dbus -> expat, although the payload links only libc. This
# test walks the exact profile closure at the recipe layer and fails if
# gcc-libs is reachable; it is the general backstop that catches the same
# shape arising through another package later (the recipe-rules.sh
# incident block pins this specific instance).
#
# Method notes, all load-bearing:
# - Runtime closure only: depends=, never makedepends= (build inputs do
#   not install). No recipe in this tree uses provides: or so: edges
#   (verified 2026-10-31: zero matches tree-wide), so package-name edges
#   are the whole graph and a recipe-level walk is exact for membership.
#   Version pins (=, ~, >, <) affect versions, never membership.
# - Depends blocks are extracted textually (never sourced): no recipe
#   code executes in this test.
# - uefi-systemd and bios-systemd share the minimal-systemd profile, so
#   one walk covers both images. The scratch image build remains the
#   solver-ground-truth proof; this test is the cheap permanent guard.
# - expat itself MUST stay in the closure (dbus links libexpat): the fix
#   removes the dep, never the library. systemd and dbus membership are
#   asserted as walk-sanity guards against a silently broken walk.
#
# usage: minimal-systemd-closure.sh (operates on the source tree it lives in)

set -eu

here=$(cd -- "$(dirname -- "$0")" && pwd)
root=$(cd -- "$here/../.." && pwd)
profiles=$here/../files/profiles

failures=0
ok() { printf 'ok       %s\n' "$*"; }
bad() { printf 'FAIL     %s\n' "$*" >&2; failures=$((failures + 1)); }

[ -f "$profiles/minimal-systemd" ] ||
	{ bad "profile missing: $profiles/minimal-systemd"; exit 1; }

# Recipe directory for a final dependency name: -dev/-doc/-libs splits
# map to their base recipe. Anything else must be a recipe directory,
# otherwise the walk fails closed (a typo must never read as clean).
recipe_dir()
{
	name=$1
	if [ -d "$root/$name" ]; then
		printf '%s' "$name"
		return 0
	fi
	case $name in
		*-dev | *-doc | *-libs)
			base=${name%-*}
			if [ -d "$root/$base" ]; then
				printf '%s' "$base"
				return 0
			fi
			;;
	esac
	return 1
}

# Textual depends= extraction (never sources recipe code): handles the
# single-line form and the multi-line block form, skips makedepends.
recipe_depends()
{
	awk '
	/^depends="/ {
		line = $0; sub(/^depends="/, "", line)
		if (line ~ /"$/) { sub(/"$/, "", line); if (line != "") print line; next }
		if (line != "") print line
		inblock = 1
		next
	}
	/^makedepends="/ {
		if ($0 ~ /"$/) next
		inblock = -1
		next
	}
	inblock == 1 {
		line = $0
		if (line ~ /"$/) { sub(/"$/, "", line); if (line != "") print line; inblock = 0; next }
		print line
		next
	}
	inblock == -1 {
		if ($0 ~ /"$/) inblock = 0
		next
	}' "$root/$1/recipe.sh"
}

intentions=$(awk '{ line = $0; sub(/#.*$/, "", line); gsub(/^[ \t]+|[ \t]+$/, "", line) }
	line == "" { next } { print line }' "$profiles/minimal-systemd" | tr '\n' ' ')
[ -n "$intentions" ] || { bad "profile has no intentions"; exit 1; }

visited=" "
queue="$intentions"
while [ -n "$queue" ]; do
	token=${queue%% *}
	case $queue in
		*" "*) queue=${queue#* } ;;
		*) queue= ;;
	esac
	[ -n "$token" ] || continue
	case $visited in
		*" $token "*) continue ;;
	esac
	dir=$(recipe_dir "$token") ||
		{ bad "unknown package in closure: $token"; exit 1; }
	visited="$visited$token "
	deps=$(recipe_depends "$dir")
	for d in $deps; do
		# $pkgname refs expand to the recipe that declares them; pins
		# (=, ~, >, <) affect versions, never membership.
		d=${d//\$pkgname/$dir}
		clean=${d%%[=~<>]*}
		[ -n "$clean" ] || continue
		case $visited in
			*" $clean "*) ;;
			*) queue="$queue $clean" ;;
		esac
	done
done

printf 'closure members: %s\n' "$(printf '%s' "$visited" | wc -w)"

for want in expat systemd dbus; do
	case $visited in
		*" $want "*) ok "$want is in the minimal-systemd closure" ;;
		*) bad "$want is missing from the closure (walk is broken)" ;;
	esac
done

case $visited in
	*" gcc-libs "*) bad "gcc-libs is reachable in the minimal-systemd closure" ;;
	*) ok "gcc-libs is not reachable in the minimal-systemd closure" ;;
esac

[ "$failures" -eq 0 ] || exit 1
printf 'minimal-systemd closure: OK (no gcc-libs)\n'
