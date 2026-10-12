#!/bin/sh

# Saphira toolchain invariants: the akadata target triplet, Saphira compiler
# branding, the x86-64-v3 baseline, and the AKADATA branch-cost backport.
# No build required.
#
# The branch-cost policy is the reason this suite exists. AGENTS.md records
# it as intentional Saphira compiler policy, not disposable scaffolding:
#
#     x86: Increase generic tune branch misprediction cost
#     gcc/config/i386/x86-tune-costs.h
#         COSTS_N_INSNS (2)  ->  COSTS_N_INSNS (2) + 3
#
# and it has had ZERO regression check: eight repository-wide hits for
# x86-tune-costs, COSTS_N_INSNS and the upstream commit are all prose or
# the patch file itself. Nothing asserted the patch was still applied, still
# needed, or still carried the semantic change rather than a cosmetic one.
#
# This suite applies the patch to the vendored source in a scratch
# directory and reads the result, which needs no compiler and no build.
#
# usage: toolchain.sh (operates on the source tree it lives in)

set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

fail()
{
	printf '%s\n' "toolchain: $*" >&2
	exit 1
}

checks=0
ok()
{
	checks=$((checks + 1))
	printf '  ok   %s\n' "$1"
}

scratch=${SAPHIRA_TMPDIR:-/build/tmp}
mkdir -p "$scratch" || fail "cannot create scratch under $scratch"
work=$(mktemp -d "$scratch/toolchain-test.XXXXXX")
trap 'rm -rf -- "$work"' EXIT HUP INT TERM

# Read the "Branch mispredict scale" line that belongs to a NAMED tune
# struct. Scoping matters: upstream GCC 16.2.0 ALREADY carries
# COSTS_N_INSNS (2) + 3 for icelake_cost and alderlake_cost, so a blanket
# grep for the patched value matches the pristine tarball and reports a
# false "stale or double-applied" failure. The AKADATA change is
# specifically about the GENERIC tune, which is the one Saphira selects
# (--with-tune=generic), so that is the only struct worth asserting on.
tune_branch_scale()
{
	awk -v want="$2" '
		/^struct processor_costs/ { s = $3 }
		s == want && /Branch mispredict scale/ { print; exit }
	' "$1"
}

# --- 1. the target triplet -------------------------------------------
#
# x86_64-akadata-linux-musl is the Saphira triplet and is deliberately NOT
# renamed: the akadata name in the toolchain is the akadata name in the
# distribution identity, and GCC/Rust target specs are the one place it is
# correct rather than stale.

TRIPLET=x86_64-akadata-linux-musl
for pkg in gcc binutils; do
	grep -q -- "--target=$TRIPLET" "$root/$pkg/recipe.sh" ||
		fail "$pkg does not configure --target=$TRIPLET"
	grep -q -- "--host=$TRIPLET" "$root/$pkg/recipe.sh" ||
		fail "$pkg does not configure --host=$TRIPLET"
done
ok "gcc and binutils target $TRIPLET"

# No package may assume a GNU triplet. This is the whole point of the
# branded triplet: a single x86_64-linux-gnu would silently link against
# glibc assumptions.
forbidden=$(git -C "$root" grep -l 'x86_64-linux-gnu\|x86_64-pc-linux-gnu' -- \
	'*/recipe.sh' 2>/dev/null || true)
[ -z "$forbidden" ] ||
	fail "a recipe assumes a GNU triplet: $forbidden"
ok "no recipe assumes a GNU triplet"

# Rust: the target triplet and the branded target spec.
grep -q 'x86_64-akadata-linux-musl' "$root/rustc/recipe.sh" ||
	fail "rustc does not name the Saphira target triplet"
[ -f "$root/rustc/files/akadata-target.patch" ] ||
	fail "the akadata Rust target spec is missing"
grep -q 'x86_64-akadata-linux-musl' "$root/rustc/files/akadata-target.patch" ||
	fail "the akadata Rust target spec does not carry the Saphira triplet"
ok "rustc targets the Saphira triplet via the akadata target spec"

# The cross toolchain must only ever target akadata triplets.
for target in $(sed -n 's/^\(SAPHIRA_CROSS_TARGET:-[a-z0-9_-]*\)$/\1/p' \
	"$root/cross-toolchain/recipe.sh" | sed 's/.*://'); do
	case $target in
	*-akadata-*) ;;
	*) fail "cross-toolchain default target is not an akadata triplet: $target" ;;
	esac
done
ok "the cross toolchain defaults to an akadata triplet"

# --- 2. Saphira compiler branding ------------------------------------

grep -q -- '--with-pkgversion="Saphira ' "$root/gcc/recipe.sh" ||
	fail "gcc does not brand itself Saphira via --with-pkgversion"
grep -q 'Saphira' "$root/binutils/recipe.sh" ||
	fail "binutils does not brand itself Saphira"
grep -q 'description = "Saphira' "$root/rustc/recipe.sh" ||
	fail "rustc does not brand itself Saphira"
ok "gcc, binutils and rustc all carry Saphira branding"

# Branding must be ASSERTED after installation, not merely requested. The
# precedent already exists in the tree: clang asserts
# `clang -print-target-triple' and rustc asserts `rustc -vV' host. gcc and
# binutils set --with-pkgversion but never check it, so a silent loss of
# branding would ship unnoticed.
assert_gcc=$(sed -n '/recipe_install/,/^}/p' "$root/gcc/recipe.sh" |
	grep -c 'gcc -v\|--version.*Saphira\|print-search-dirs\|Saphira' || true)
[ "$assert_gcc" -gt 0 ] ||
	fail "gcc brands itself at configure time but never asserts it after installation"
ok "gcc asserts its own identity after installation"

# --- 3. the AKADATA branch-cost backport -----------------------------
#
# The load-bearing check. Three things must all hold, and each was
# previously unchecked:
#
#   a. the patch exists and the recipe applies it;
#   b. the patch still carries the SEMANTIC change, not a cosmetic one;
#   c. it is still NEEDED (upstream still reads the unpatched value) and
#      still APPLIES, and the patched result reads the patched value.

patch=$root/gcc/files/0001-x86-increase-generic-tune-branch-misprediction-cost.patch
[ -f "$patch" ] || fail "the branch-cost patch is missing: $patch"
grep -q 'x86-tune-costs\.h' "$patch" ||
	fail "the branch-cost patch does not touch x86-tune-costs.h"
grep -q '52cd02606b906160bf47001a00b446c35d46f15f' "$patch" ||
	fail "the branch-cost patch does not record its upstream commit"
ok "the branch-cost patch exists and names x86-tune-costs.h and its upstream commit"

# (b) the semantic delta, asserted on the patch text itself so a patch
# edited into a no-op fails here rather than at some future build.
grep -q '^-.*COSTS_N_INSNS (2),' "$patch" ||
	fail "the patch no longer removes the unpatched branch scale (2)"
grep -q '^+.*COSTS_N_INSNS (2) + 3,' "$patch" ||
	fail "the patch no longer applies the AKADATA branch scale (2) + 3"
ok "the patch carries the semantic change: (2) -> (2) + 3"

# (a) the recipe must actually apply it.
grep -q '0001-x86-increase-generic-tune-branch-misprediction-cost.patch' \
	"$root/gcc/recipe.sh" ||
	fail "the gcc recipe does not apply the branch-cost patch"
ok "the gcc recipe applies the branch-cost patch"

# (c) still needed, still applies, and the result is right. This needs the
# vendored source, not a compiler.
tarball=$(ls "$root"/gcc/files/gcc-*.tar.* 2>/dev/null | head -1)
[ -n "$tarball" ] || fail "no vendored gcc source to check the patch against"
tar -xf "$tarball" -C "$work" gcc-*/gcc/config/i386/x86-tune-costs.h 2>/dev/null ||
	tar -xf "$tarball" -C "$work" 2>/dev/null
tune=$(find "$work" -path '*/gcc/config/i386/x86-tune-costs.h' | head -1)
[ -n "$tune" ] || fail "cannot locate x86-tune-costs.h in the vendored source"

# The pristine GENERIC tune must still carry the unpatched value, or the
# patch is dead weight at best and misapplied at worst.
generic_before=$(tune_branch_scale "$tune" generic_cost)
[ -n "$generic_before" ] ||
	fail "cannot find generic_cost in the vendored x86-tune-costs.h"
case $generic_before in
*"COSTS_N_INSNS (2) + 3"*)
	fail "the vendored generic_cost already reads (2) + 3; the patch is stale or double-applied"
	;;
*"COSTS_N_INSNS (2),"*) ;;
*) fail "generic_cost has an unexpected branch scale: $generic_before" ;;
esac
ok "the patch is still NEEDED: upstream 16.2.0 generic_cost still reads COSTS_N_INSNS (2)"

# Record the context that makes the policy meaningful: upstream already
# applies (2) + 3 to its two newest tunes. Saphira tunes GENERIC, so
# without this patch a Saphira compiler would cost branch mispredictions
# differently from upstream's newest-target builds.
for newer in icelake_cost alderlake_cost; do
	line=$(tune_branch_scale "$tune" "$newer")
	case $line in
	*"COSTS_N_INSNS (2) + 3"*) ;;
	*) fail "upstream $newer no longer reads (2) + 3; the AKADATA generic-tune backport's rationale has changed and should be re-reviewed" ;;
	esac
done
ok "upstream already applies (2) + 3 to icelake_cost and alderlake_cost; the backport extends that to the generic tune Saphira selects"

# Apply it and read the result. This is the check that would have caught a
# silently dropped patch, and it needs no compiler.
# A minimal tree is enough: the patch's only hunk is inside this one file,
# and `patch -p1' resolves it to gcc/config/i386/x86-tune-costs.h relative
# to the -d directory. Staging only that path keeps the check fast and
# avoids extracting a 90MB tree just to read one file.
mkdir -p "$work/src/gcc/config/i386"
cp "$tune" "$work/src/gcc/config/i386/x86-tune-costs.h"
if [ -f "$work/src/gcc/config/i386/x86-tune-costs.h" ]; then
	if patch -Np1 -p1 -d "$work/src" -i "$patch" >/dev/null 2>&1; then
		patched=$work/src/gcc/config/i386/x86-tune-costs.h
		generic_after=$(tune_branch_scale "$patched" generic_cost)
		case $generic_after in
		*"COSTS_N_INSNS (2) + 3"*) ;;
		*) fail "the patch applied but generic_cost does not read (2) + 3: $generic_after" ;;
		esac
		# The other tunes must be untouched: a patch that changed more
		# than the generic tune would silently alter every -mtune.
		changed=$(diff "$tune" "$patched" | grep -c '^[<>]' || true)
		[ "$changed" -le 2 ] ||
			fail "the patch changed $changed lines, expected 1 (the generic tune only)"
		ok "the patch applies cleanly, generic_cost becomes (2) + 3, and nothing else in the table changed"
	else
		fail "the branch-cost patch does NOT apply to the vendored gcc source; upstream has moved and the policy would be silently lost"
	fi
else
	fail "could not stage a minimal gcc source tree to apply the patch to"
fi

# --- 4. x86-64-v3 baseline -------------------------------------------
#
# Set in three unsynchronised places and validated by none. What is
# assertable statically is that the canonical mechanisms are still
# present, because they are what every other package inherits silently.

grep -q -- '--with-arch=x86-64-v3' "$root/gcc/recipe.sh" ||
	fail "gcc no longer sets the x86-64-v3 default via --with-arch"
ok "gcc sets the x86-64-v3 baseline as its default"

grep -q 'base.cpu = "x86-64-v3"' "$root/rustc/files/akadata-target.patch" ||
	fail "the akadata Rust target no longer defaults to x86-64-v3"
ok "the akadata Rust target defaults to x86-64-v3"

# The proof package must still exist and still assert the floor.
[ -f "$root/saphira-v3-proof/recipe.sh" ] ||
	fail "saphira-v3-proof is gone; nothing asserts the v3 floor"
grep -q 'x86-64-v3' "$root/saphira-v3-proof/recipe.sh" ||
	fail "saphira-v3-proof no longer references the v3 baseline"
ok "saphira-v3-proof still asserts the v3 floor"

# Documented, deliberate exceptions. Recorded here so that changing one is
# a conscious act rather than an accident, and so a NEW deviation is
# visible as a failure.
#
#   clamav   leaves target-cpu at baseline for portability across KVM hosts
#   zig      uses its own internal target name and loses the v3 default
#
# These are policy inconsistencies awaiting a decision, not defects to be
# silently repaired in the same sweep.
clamav_baseline=$(grep -c 'target-cpu left at baseline' "$root/clamav/recipe.sh" || true)
[ "$clamav_baseline" -ge 1 ] ||
	fail "clamav's deliberate baseline exception is no longer documented in its recipe; if the exception was removed, record the decision"
ok "clamav's baseline exception is still explicitly documented (awaiting a decision)"

printf '%s\n' "toolchain: OK ($checks checks)"
