#!/bin/sh

# kernel-layout: the saphira-kernel runtime module-tree gate.
#
# usage: kernel-layout.sh INSTALL-KERNEL-LAYOUT-SH
#
# The gate was INVERTED in the r10 corrective release. It used to require
# lib/modules/<rel>/build -> /usr/src/<tree> and then walk that tree checking
# Makefile, .config, Module.symvers, the generated UAPI syscall header, modpost
# and sign-file. Those assertions are why d2e581d had to ship the prepared tree
# in a RUNTIME package, which cost 1648 MiB and 77,655 files and grew every
# installed rootfs to roughly 3 GiB.
#
# A runtime package must now carry NO build tree and NO build pointer. This
# suite covers the positive case and, more importantly, the four ways a build
# tree could creep back in -- each of which must FAIL, because a gate nobody
# has seen reject is not a gate.

set -eu

[ "$#" -eq 1 ] || {
	printf 'usage: %s INSTALL-KERNEL-LAYOUT-SH\n' "$0" >&2
	exit 1
}
helper=$1
[ -f "$helper" ] || { printf 'no such file: %s\n' "$helper" >&2; exit 1; }

test_root=${SAPHIRA_TMPDIR:-/build/tmp}/kernel-layout-test
rm -rf "$test_root"
mkdir -p "$test_root"
trap 'rm -rf "$test_root"' EXIT

pass=0
fail=0
ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
no() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

. "$helper"

KREL=7.2.2

# A minimal VALID runtime payload: a module dir with depmod metadata and at
# least one module, and nothing else.
make_valid()
{
	_root=$1
	rm -rf "$_root"
	mkdir -p "$_root/lib/modules/$KREL/kernel/virt"
	: >"$_root/lib/modules/$KREL/kernel/virt/dummy.ko"
	printf 'kernel/virt/dummy.ko:\n' >"$_root/lib/modules/$KREL/modules.dep"
	printf 'kernel/virt/dummy.ko:\n' >"$_root/lib/modules/$KREL/modules.softdep"
	printf 'alias dummy\n' >"$_root/lib/modules/$KREL/modules.alias"
	printf '\n' >"$_root/lib/modules/$KREL/modules.order"
}

# ------------------------------------------------------------- positive case
make_valid "$test_root/pk"
if check_module_layout "$test_root/pk" "$KREL" "$KREL" >/dev/null 2>&1; then
	ok "a clean runtime module tree is accepted"
else
	no "a clean runtime module tree was rejected"
fi

# ------------------------------------------------- the four ways to regress
# 1. /usr/src present at all.
make_valid "$test_root/a"
mkdir -p "$test_root/a/usr/src/linux-$KREL-saphira"
if check_module_layout "$test_root/a" "$KREL" "$KREL" >/dev/null 2>&1; then
	no "a payload shipping /usr/src was ACCEPTED"
else
	ok "a payload shipping /usr/src is rejected"
fi

# 2. the build symlink upstream modules_install creates.
make_valid "$test_root/b"
ln -s /usr/src/linux-$KREL-saphira "$test_root/b/lib/modules/$KREL/build"
if check_module_layout "$test_root/b" "$KREL" "$KREL" >/dev/null 2>&1; then
	no "a payload shipping lib/modules/$KREL/build was ACCEPTED"
else
	ok "a payload shipping the build symlink is rejected"
fi

# 3. the source symlink.
make_valid "$test_root/c"
ln -s /build/stage/source "$test_root/c/lib/modules/$KREL/source"
if check_module_layout "$test_root/c" "$KREL" "$KREL" >/dev/null 2>&1; then
	no "a payload shipping lib/modules/$KREL/source was ACCEPTED"
else
	ok "a payload shipping the source symlink is rejected"
fi

# 4. a DANGLING build symlink. Shipping a link that can only dangle helps
#    nobody and misleads whoever debugs the next thing, so it is refused too.
make_valid "$test_root/d"
ln -s /usr/src/gone "$test_root/d/lib/modules/$KREL/build"
if check_module_layout "$test_root/d" "$KREL" "$KREL" >/dev/null 2>&1; then
	no "a DANGLING build symlink was ACCEPTED"
else
	ok "a dangling build symlink is rejected"
fi

# 5. a symlink anywhere else pointing into a build tree.
make_valid "$test_root/e"
mkdir -p "$test_root/e/usr/local/lib"
ln -s /build/saphira-kernel/source "$test_root/e/usr/local/lib/src"
if check_module_layout "$test_root/e" "$KREL" "$KREL" >/dev/null 2>&1; then
	no "a payload with a /build pointer was ACCEPTED"
else
	ok "a payload with a /build pointer is rejected"
fi

# 6. missing depmod metadata must still fail.
make_valid "$test_root/f"
rm -f "$test_root/f/lib/modules/$KREL/modules.dep"
if check_module_layout "$test_root/f" "$KREL" "$KREL" >/dev/null 2>&1; then
	no "a payload missing modules.dep was ACCEPTED"
else
	ok "a payload missing modules.dep is rejected"
fi

# 7. an empty module tree must fail.
make_valid "$test_root/g"
rm -f "$test_root/g/lib/modules/$KREL"/kernel/virt/dummy.ko
if check_module_layout "$test_root/g" "$KREL" "$KREL" >/dev/null 2>&1; then
	no "an empty module tree was ACCEPTED"
else
	ok "an empty module tree is rejected"
fi

# 8. the wrong argument count is refused rather than silently accepted.
if check_module_layout "$test_root/pk" "$KREL" >/dev/null 2>&1; then
	no "a 2-argument call was ACCEPTED"
else
	ok "a wrong-arity call is refused"
fi

printf 'kernel-layout: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
