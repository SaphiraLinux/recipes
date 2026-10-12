#!/bin/sh

# saphira-build: a recipe's own subpackages must not become its dependencies.
#
# recipe_info() built its dependency list from
#
#     printf "deps=%s\n" "$depends $makedepends $subpackages"
#
# and norm_dep() reduces a -dev/-doc suffix to the base package name, so a
# recipe declaring
#
#     subpackages="$pkgname-dev"
#
# computed a dependency on "$pkgname" - itself. dep_state() then looked up the
# package's own queue row, and for a package that has never been published
# that row is BLOCKED, which is a HARD blocker. So:
#
#     mhash -> BLOCKED, waiting for mhash-dev
#            -> mhash-dev only exists as an output of mhash's own build
#            -> mhash can never build, so it is never published
#            -> deadlock
#
# mhash sat in exactly that state and blocked 23 packages behind it. liburcu
# was self-blocked the same way via -dev and -doc.
#
# It looked like it only affected new recipes because dep_state() is
# satisfied by a PUBLISHED version: once a package is published its
# subpackages exist in the index and the phantom dependency resolves. So
# every published package with subpackages masked the bug, and only the
# never-published ones deadlocked - which is why 184 recipes declaring
# subpackages produced two visible casualties instead of 184.
#
# A real build-time need for another package's -dev output belongs in
# makedepends, stated rather than inferred. wendzelnntpd depends on
# mhash-dev (it hard-requires libmhash with SHA-256) and that must survive.

set -u

SB=${1:-"$(dirname "$0")/../files/saphira-build"}
[ -f "$SB" ] || SB=/usr/bin/saphira-build
[ -f "$SB" ] || { echo "saphira-build not found" >&2; exit 2; }

pass=0
fail=0
ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
no() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }
check() { if [ "$1" = "$2" ]; then ok "$3"; else no "$3 (want '$1', got '$2')"; fi; }

echo "saphira-build subpackages-are-not-dependencies contract"
echo "  saphira-build: $SB"

# --- 1. subpackages are excluded from the derived dependency list -----------
if grep -q 'deps=%s\\n" "\$depends \$makedepends \$subpackages"' "$SB"; then
	no 'subpackages are NOT included in the computed deps'
else
	ok 'subpackages are NOT included in the computed deps'
fi
if grep -qF 'printf "deps=%s\\n" "$depends $makedepends"\n' "$SB"; then
	ok 'deps is computed from depends and makedepends only'
else
	no 'deps is computed from depends and makedepends only'
fi
# The rationale must survive, so the next reader does not "restore" it.
if grep -q 'subpackages are OUTPUTS, not inputs' "$SB"; then
	ok 'the outputs-are-not-inputs rationale is documented'
else
	no 'the outputs-are-not-inputs rationale is documented'
fi

# --- 2. behavioural: run the daemon's own derivation on real recipes --------
deps_for() {
	/bin/sh -c '. "$1" >/dev/null 2>&1
printf "%s" "$depends $makedepends"' sh "$1/recipe.sh" 2>/dev/null
}
REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)

if [ -f "$REPO_ROOT/mhash/recipe.sh" ]; then
	d=$(deps_for "$REPO_ROOT/mhash")
	case " $d " in
		*" mhash "*|*mhash-dev*|*mhash-doc*)
			no "mhash does not depend on itself (got: $d)" ;;
		*)
			ok "mhash does not depend on itself (got: $d)" ;;
	esac
	# it must still build against gcc and make
	case " $d " in
		*" gcc make "*|*" make gcc "*) ok 'mhash keeps its real build deps' ;;
		*) no "mhash keeps its real build deps (got: $d)" ;;
	esac
fi

if [ -f "$REPO_ROOT/liburcu/recipe.sh" ]; then
	d=$(deps_for "$REPO_ROOT/liburcu")
	case " $d " in
		*"liburcu-dev"*|*"liburcu-doc"*|*" liburcu "*)
			no "liburcu does not depend on its own -dev/-doc (got: $d)" ;;
		*)
			ok "liburcu does not depend on its own -dev/-doc (got: $d)" ;;
	esac
fi

# --- 3. a genuine cross-package -dev dependency must SURVIVE ----------------
if [ -f "$REPO_ROOT/wendzelnntpd/recipe.sh" ]; then
	d=$(deps_for "$REPO_ROOT/wendzelnntpd")
	case " $d " in
		*mhash-dev*) ok 'wendzelnntpd still declares mhash-dev in makedepends' ;;
		*) no "wendzelnntpd still declares mhash-dev in makedepends (got: $d)" ;;
	esac
fi

# --- 4. tree sweep: the daemon must inject no self-dependency ---------------
# Two distinct things can make a package depend on itself, and they must not be
# conflated. The daemon INJECTING one is the bug fixed here and must be zero.
# A recipe that HAND-WRITES its own subpackage into makedepends is a separate,
# pre-existing recipe bug; it is reported, not silently tolerated.
injected=0
written=0
for r in "$REPO_ROOT"/*/recipe.sh; do
	[ -f "$r" ] || continue
	pkgdir=$(dirname "$r")
	name=$(/bin/sh -c '. "$1" >/dev/null 2>&1; printf "%s" "$pkgname"' sh "$r" 2>/dev/null)
	subs=$(/bin/sh -c '. "$1" >/dev/null 2>&1; printf "%s" "$subpackages"' sh "$r" 2>/dev/null)
	[ -n "$subs" ] || continue
	deps=$(deps_for "$pkgdir")
	declared=$(/bin/sh -c '. "$1" >/dev/null 2>&1; printf "%s" "$depends $makedepends"' sh "$r" 2>/dev/null)
	for s in $subs; do
		base=${s%-dev}; base=${base%-doc}; base=${base%-static}
		base=${base%-openrc}; base=${base%-lang}
		[ "$base" = "$name" ] || continue
		case " $deps " in *" $base "*|*" $s "*) ;; *) continue ;; esac
		# present in the recipe's OWN depends/makedepends text?
		case " $declared " in
			*" $base "*|*" $s "*)
				written=$((written + 1))
				echo "        hand-written self-dependency: $name -> $s" ;;
			*)
				injected=$((injected + 1))
				echo "        daemon-injected self-dependency: $name -> $s" ;;
		esac
	done
done
check "0" "$injected" 'the daemon injects no self-dependency anywhere in the tree'
if [ "$written" -gt 0 ]; then
	ok "$written hand-written recipe self-dependency/-ies reported above (separate recipe bug, not this fix)"
fi

# --- 5. mutation: the guard must be able to fail ----------------------------
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
python3 - "$SB" "$tmp/mutant" <<'MUT'
import sys
B = chr(92)
src = open(sys.argv[1]).read()
old = 'printf "deps=%s' + B + B + 'n" "$depends $makedepends"' + B + 'n'
new = 'printf "deps=%s' + B + B + 'n" "$depends $makedepends $subpackages"' + B + 'n'
assert src.count(old) == 1, "anchor count %d" % src.count(old)
open(sys.argv[2], "w").write(src.replace(old, new, 1))
MUT
if [ ! -s "$tmp/mutant" ]; then
	no 'mutation could not be applied (this check would be vacuous)'
elif grep -qF 'makedepends $subpackages' "$tmp/mutant"; then
	ok 'mutation restores $subpackages into deps and the guard would catch it'
else
	no 'mutation was a no-op (guard is vacuous)'
fi

echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
echo "saphira-build subpackages-not-deps: OK"
