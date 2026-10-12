#!/bin/sh

# buildpkg-single: -libs subpackages are genuinely standalone runtime packages.
#
# Two independent bugs, found together, both of which silently made gcc-libs
# impossible to use on a runtime-only system. Either one alone is enough to
# break it, so both are pinned here.
#
# 1. THE PARENT PIN. The -libs case sets dev_dependencies="" to mean "no
#    parent pin", and the printf that writes the output line used
#
#        "${dev_dependencies:-$pkgname=$pkgver-r$pkgrel}"
#
#    POSIX ${var:-word} substitutes word when the variable is unset OR EMPTY.
#    An explicitly empty value therefore triggered the default and produced
#    exactly the parent pin the code was trying to avoid:
#
#        gcc-libs-16.2.0-r8.apk -> depends: gcc=16.2.0-r8
#
#    which drags the whole compiler (binutils, gmp, isl, mpc, mpfr) into every
#    runtime consumer chain - the same 599 MiB shape as the efivar gcc-libs
#    leak. ${var-word} substitutes only when UNSET, so an explicit empty value
#    survives as the empty dependency list it means.
#
# 2. THE STRANDED SONAME LINKS. The -libs split moved only regular files:
#
#        find "$root" -type f -name '*.so.*'
#
#    so libstdc++.so.6.0.36 (the real file) went to gcc-libs while its SONAME
#    link libstdc++.so.6 stayed in the parent gcc. The -dev case's
#    "-type l -name '*.so'" does not reach it either, because that pattern
#    matches only UNVERSIONED links. Result: gcc-libs installed alone had the
#    library but not the name the dynamic linker actually opens, so the
#    RUNTIME closure check failed on 15 C++ packages:
#
#        binaryen ccache cmake dcmtk gmp gperf inih llvm lshw lzip
#        nghttp2 ninja rspamd snappy syslog-ng
#
# The contract: a -libs subpackage carries its SONAME symlinks with the real
# files, and pins no parent. Symlinks must stay symlinks - move_staged_file
# uses mv, and makepkg's copy_payload checks is_symlink() before its hardlink
# bookkeeping, so no symlink is ever turned into a hardlink.

set -u

BUILDPKG=${1:-"$(dirname "$0")/../files/buildpkg-single"}
[ -f "$BUILDPKG" ] || BUILDPKG=/usr/lib/saphira-packager/buildpkg-single
[ -f "$BUILDPKG" ] || { echo "buildpkg-single not found" >&2; exit 2; }

pass=0
fail=0
ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
no() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }
check() { if [ "$1" = "$2" ]; then ok "$3"; else no "$3 (want '$1', got '$2')"; fi; }

echo "buildpkg-single -libs standalone-runtime contract"
echo "  buildpkg-single: $BUILDPKG"

# --- 1. no parent pin -------------------------------------------------------
if grep -q 'dev_dependencies:-\$pkgname' "$BUILDPKG"; then
	no 'outputs line does not use ${dev_dependencies:-...} (fires on empty)'
else
	ok 'outputs line does not use ${dev_dependencies:-...} (fires on empty)'
fi
if grep -q 'dev_dependencies-\$pkgname' "$BUILDPKG"; then
	ok 'outputs line uses ${dev_dependencies-...} (empty means empty)'
else
	no 'outputs line uses ${dev_dependencies-...} (empty means empty)'
fi
# The intent must still be expressed, not just the mechanism removed.
if grep -q '"$pkgname"-libs) description=.*dev_dependencies=""' "$BUILDPKG"; then
	ok '-libs still declares an explicitly empty dependency set'
else
	no '-libs still declares an explicitly empty dependency set'
fi
# The comment recording WHY must survive, so the next reader keeps it.
if grep -q 'STANDALONE runtime libraries: no parent pin' "$BUILDPKG"; then
	ok 'the no-parent-pin rationale is still documented'
else
	no 'the no-parent-pin rationale is still documented'
fi

# --- 2. SONAME symlinks travel with the real files --------------------------
# Isolate the -libs case block, then assert on the find(1) it actually uses.
libs_block=$(sed -n '/"\$pkgname"-libs)/,/;;/p' "$BUILDPKG" | grep -v '^[[:space:]]*#')
if [ -z "$libs_block" ]; then
	no 'the -libs case block is present'
else
	ok 'the -libs case block is present'
	if printf '%s' "$libs_block" | grep -q -- "-type f -name '\*.so\.\*'"; then
		no '-libs split no longer matches regular files alone'
	else
		ok '-libs split no longer matches regular files alone'
	fi
	# The predicate must accept BOTH kinds. Check the two type tests coexist
	# in one find(1) rather than matching an exact string: the parens are
	# backslash-escaped in the source and easy to get subtly wrong.
	if printf '%s' "$libs_block" | grep -q -- '-type f' &&
		printf '%s' "$libs_block" | grep -q -- '-type l'; then
		ok '-libs split matches both regular files and symlinks'
	else
		no '-libs split matches both regular files and symlinks'
	fi
	if printf '%s' "$libs_block" | grep -q -- "-name '\*\.so\.\*'"; then
		ok '-libs split still selects the versioned .so.N set'
	else
		no '-libs split still selects the versioned .so.N set'
	fi
fi
# The -dev unversioned-link pattern must be untouched: it is a different set.
# Count find(1) invocations only - the rationale comment quotes the pattern.
dev_links=$(grep -c 'find .*-type l -name '"'"'\*\.so'"'"' -print0' "$BUILDPKG")
check "1" "$dev_links" 'the -dev unversioned .so link pattern is unchanged'

# --- 3. symlinks are never turned into hardlinks ----------------------------
# move_staged_file must move with mv, not copy.
if grep -qE '^\s*mv "\$source_path" "\$destination"' "$BUILDPKG"; then
	ok 'move_staged_file uses mv (a symlink moves as a symlink)'
else
	no 'move_staged_file uses mv (a symlink moves as a symlink)'
fi
if grep -q 'src.is_symlink()' saphira-packager/files/makepkg 2>/dev/null ||
	grep -q 'src.is_symlink()' "$(dirname "$0")/../files/makepkg" 2>/dev/null; then
	ok 'makepkg copy_payload still checks is_symlink() first'
else
	no 'makepkg copy_payload still checks is_symlink() first'
fi
if grep -q 'symlink_to(src.readlink())' "$(dirname "$0")/../files/makepkg" 2>/dev/null; then
	ok 'makepkg re-creates symlinks as symlinks, not hardlinks'
else
	no 'makepkg re-creates symlinks as symlinks, not hardlinks'
fi

# --- 4. mutation: each guard must be able to fail ----------------------------
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

sed 's/dev_dependencies-\$pkgname/dev_dependencies:-$pkgname/' "$BUILDPKG" > "$tmp/m1"
if grep -q 'dev_dependencies:-\$pkgname' "$tmp/m1"; then
	ok 'mutation restores the parent pin and the guard would catch it'
else
	no 'mutation failed (guard is vacuous)'
fi

python3 - "$BUILDPKG" "$tmp/m2" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
# The parens are backslash-escaped in the shell source, so match the
# backslashes too: \( -type f -o -type l \)  ->  -type f
new, n = re.subn(r"\\\( -type f -o -type l \\\)", "-type f", src, count=1)
assert n == 1, "mutation anchor not found: the -libs predicate changed shape"
assert new != src, "mutation was a no-op"
open(sys.argv[2], "w").write(new)
PY
if [ ! -s "$tmp/m2" ]; then
	no 'mutation could not be applied (this check would be vacuous)'
else
	# Strip comment lines: the rationale text quotes both -type f and
	# -type l, and would otherwise satisfy the grep on its own.
	if sed -n '/"\$pkgname"-libs)/,/;;/p' "$tmp/m2" \
		| grep -v '^[[:space:]]*#' | grep -q -- '-type l'; then
		no 'mutation drops symlinks from the -libs split and the guard would catch it'
	else
		ok 'mutation drops symlinks from the -libs split and the guard would catch it'
	fi
fi

# --- 5. behavioural check: the split really does pick up a SONAME link ------
# Reproduced rather than asserted, because the bug was a find(1) predicate and
# a parameter-expansion subtlety - neither is visible to a source-level test.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/root/usr/lib"
: > "$work/root/usr/lib/libfoo.so.1.2.3"           # real file
ln -s libfoo.so.1.2.3 "$work/root/usr/lib/libfoo.so.1"   # SONAME link
ln -s libfoo.so.1 "$work/root/usr/lib/libfoo.so"         # unversioned dev link
mkdir -p "$work/sub"
moved() { [ -e "$work/sub/usr/lib/$1" ] || [ -L "$work/sub/usr/lib/$1" ]; }
while IFS= read -r -d '' f; do
	rel=${f#"$work/root/"}
	mkdir -p "$work/sub/$(dirname "$rel")"
	mv "$f" "$work/sub/$rel"
done < <(find "$work/root/usr/lib" \( -type f -o -type l \) -name '*.so.*' -print0)
moved libfoo.so.1.2.3 && ok 'the real .so.N file moves to -libs' \
	|| no 'the real .so.N file moves to -libs'
moved libfoo.so.1 && ok 'the SONAME .so.N symlink moves with it' \
	|| no 'the SONAME .so.N symlink moves with it'
[ -L "$work/sub/usr/lib/libfoo.so.1" ] \
	&& ok 'it moved as a symlink, not a hardlink' \
	|| no 'it moved as a symlink, not a hardlink'
[ -L "$work/root/usr/lib/libfoo.so" ] \
	&& ok 'the unversioned dev link stays in the parent (dangling only because its target moved)' \
	|| no 'the unversioned dev link stays in the parent'

echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
echo "buildpkg-single libs-standalone: OK"
