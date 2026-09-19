#!/bin/sh

# logrotate.d fragment convention: static assertions that every
# files/logrotate.d/* fragment is installed exactly once under
# /etc/logrotate.d/ by its owning recipe, and that no two recipes
# claim the same installed name (the publish gate would fail such
# dual ownership, but this catches it before any build).
#
# Policy encoded (see RECIPE_RULES.md "logrotate.d fragments"):
# - fragment at <pkg>/files/logrotate.d/<name> installs to
#   $PKGDEST/etc/logrotate.d/<name>;
# - every stanza carries missingok (fragments activate before the
#   service may have written anything);
# - no journal paths; every fragment names a /var/log path.
#
# A live `logrotate -d` parse proof is deliberately NOT part of this
# static gate: stanzas with `create <mode> <user> <group>` make even
# debug runs attempt a uid switch, which fails for non-root test
# runners. Live parsing stays a per-package acceptance activity.
#
# usage: logrotate-fragments.sh (operates on the source tree it lives in)

set -eu

source_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

fail()
{
	printf '%s\n' "logrotate-fragments: $*" >&2
	exit 1
}

# installed-name -> owning recipe (duplicate ownership fails closed)
seen_names=""

for fragdir in "$source_root"/*/files/logrotate.d; do
	pkg=${fragdir%/files/logrotate.d}
	pkg=${pkg##*/}
	for frag in "$fragdir"/*; do
		[ -e "$frag" ] || continue
		name=${frag##*/}
		printf '%s' "$name" | grep -Eq '^[a-z0-9][a-z0-9+._-]*$' || \
			fail "$pkg fragment has an invalid installed name: $name"
		case $seen_names in
			*" $name "*) fail "duplicate /etc/logrotate.d/$name (also owned elsewhere)" ;;
		esac
		seen_names="$seen_names $name "
		recipe=$source_root/$pkg/recipe.sh
		grep -q "etc/logrotate.d/$name" "$recipe" || \
			fail "$pkg/files/logrotate.d/$name is never installed by its recipe"
		grep -q '/var/log/' "$frag" || \
			fail "$pkg fragment $name names no /var/log path"
		grep -q 'missingok' "$frag" || \
			fail "$pkg fragment $name lacks missingok"
		grep -q 'journal' "$frag" && \
			fail "$pkg fragment $name references journal paths"
		[ -s "$frag" ] || fail "$pkg fragment $name is empty"
		open=$(grep -o '{' "$frag" | wc -l)
		close=$(grep -o '}' "$frag" | wc -l)
		[ "$open" -eq "$close" ] && [ "$open" -ge 1 ] || \
			fail "$pkg fragment $name has unbalanced braces"
	done
done

# The logrotate package itself may only install the ownerless
# generics: anything service-specific belongs to its owner recipe.
logrotate_recipe=$source_root/logrotate/recipe.sh
for installed in $(grep -o 'etc/logrotate\.d/[a-z0-9][a-z0-9+._-]*' "$logrotate_recipe" | sort -u); do
	name=${installed##*/}
	case $name in
		wtmp|lastlog) ;;
		*) fail "logrotate recipe installs service-specific $installed (belongs to its owner recipe)" ;;
	esac
done

# Master config must exist and pull the fragment directory in.
grep -q '^include /etc/logrotate.d' "$source_root/logrotate/files/logrotate.conf" || \
	fail "logrotate master conf lacks the logrotate.d include"

printf '%s\n' 'logrotate-fragments: OK'
