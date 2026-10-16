#!/bin/sh

# kernel-source-tree: the saphira-kernel-source-* staging gate.
#
# usage: kernel-source-tree.sh KERNEL-SOURCE-TREE-SH
#
# The invariant under test:
#
#     kernel build tree  !=  kernel source package input
#
# saphira-kernel-source-<ver>-1-r1 was assembled from a USED KERNEL BUILD TREE.
# buildpkg-single runs recipe_build and recipe_install against one $SRC, and r1
# ran `make olddefconfig && make -j$(nproc)` in recipe_build before recipe_install
# copied that same directory into the payload. install_prepared_tree() then pruned
# a DENYLIST of the names someone remembered to delete, and everything it did not
# name shipped. The published 7.2.2 r1 measured 353,120,683 bytes compressed,
# installed-size 1,713,546,224, with 3,410 payload paths that the upstream tarball
# does not contain at all.
#
# This suite is the hermetic half of the guard: it drives the corrected helper
# over synthetic trees, so the gate is proven to REJECT in a second rather than
# only on the next release build. The exhaustive half is
# kernel-source-purity.sh, which diffs a published APK against the real tarball.
#
# A gate nobody has seen reject is not a gate, so rejection is the bulk of what
# follows. The positive cases matter just as much: the rules were calibrated
# against the real linux-7.2.2 tarball (101,060 entries), and an earlier revision
# wrongly rejected 10 legitimate upstream files (drivers/s390/char/defkeymap.map,
# tools/perf/util/bpf_skel/vmlinux, kernel/kheaders.c, scripts/genksyms and
# friends). A gate that refuses a correct package gets switched off, so the
# allow cases are asserted explicitly and would fail loudly if that regressed.

set -eu

[ "$#" -eq 1 ] || {
	printf 'usage: %s KERNEL-SOURCE-TREE-SH\n' "$0" >&2
	exit 1
}
helper=$1
[ -f "$helper" ] || { printf 'no such file: %s\n' "$helper" >&2; exit 1; }

test_root=${SAPHIRA_TMPDIR:-/build/tmp}/kernel-source-tree-test
rm -rf "$test_root"
mkdir -p "$test_root"
trap 'rm -rf "$test_root"' EXIT

pass=0
fail=0
ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
no() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

. "$helper"

# A tree that is a legitimate source tree: a Makefile plus the upstream files
# the rules are most likely to confuse with build output.
make_clean()
{
	_root=$1
	rm -rf "$_root"
	mkdir -p "$_root"
	: >"$_root/Makefile"
	: >"$_root/main.c"
	: >"$_root/vmlinux.lds.S"
	: >"$_root/vmlinux.lds.h"
	: >"$_root/vmlinux.h"
	: >"$_root/vmlinux.its.S"
	: >"$_root/vmlinux.scr"
	: >"$_root/vmlinux.c"
	: >"$_root/vmlinux-gdb.py"
	: >"$_root/vmlinux-kallsyms.c"
	: >"$_root/Makefile.vmlinux"
	: >"$_root/Makefile.vmlinux_a"
	: >"$_root/Makefile.vmlinux_o"
	: >"$_root/extract-vmlinux"
	: >"$_root/link-vmlinux.sh"
	: >"$_root/test_vmlinux.c"
	: >"$_root/vmlinux-nommu.lds"
	: >"$_root/vmlinux-std.lds"
	: >"$_root/vmlinux-sun3.lds"
	: >"$_root/vmlinux-xip.lds.S"
	# .map is a real upstream extension (module map files)
	mkdir -p "$_root/drivers/foo"
	: >"$_root/drivers/foo/defkeymap.map"
	: >"$_root/drivers/foo/speakupmap.map"
	# upstream commits generated-looking headers in tools/
	mkdir -p "$_root/tools/include/generated/asm"
	: >"$_root/tools/include/generated/asm-offsets.h"
	: >"$_root/tools/include/generated/asm/cpucap-defs.h"
	: >"$_root/tools/include/generated/asm/sysreg-defs.h"
	# upstream ships the kheaders stub headers and the genksyms source
	mkdir -p "$_root/usr/dummy-include/netinet" "$_root/kernel" \
		"$_root/scripts" "$_root/tools/objtool" "$_root/scripts/selinux/mdp" \
		"$_root/scripts/mod" "$_root/scripts/kconfig" "$_root/include"
	: >"$_root/usr/dummy-include/endian.h"
	: >"$_root/usr/dummy-include/limits.h"
	: >"$_root/usr/dummy-include/netinet/if_ether.h"
	: >"$_root/kernel/kheaders.c"
	: >"$_root/scripts/genksyms"
	: >"$_root/tools/objtool/Makefile"
	: >"$_root/scripts/selinux/mdp/Makefile"
	# upstream ships the PUBLIC signing key and the source of every host tool
	mkdir -p "$_root/certs"
	: >"$_root/certs/signing_key.x509"
	: >"$_root/scripts/mod/modpost.c"
	: >"$_root/scripts/sign-file.c"
	: >"$_root/tools/objtool/fixdep.c"
	: >"$_root/scripts/kconfig/conf.c"
	# ordinary source of every extension the gate claims to own
	: >"$_root/drivers/foo/hello.o.txt"
	# an in-tree symlink is source and must survive
	ln -s ../../Makefile "$_root/arch-link"
}

# gate_status ROOT - run the gate the way buildpkg-single runs it: inside a
# subshell with `set -e` active and the call NOT in a condition.
#
# This indirection exists because of a defect the first version of this suite
# could not see. Calling check_source_tree_pure from an `if` DISABLES set -e
# for the whole call, so the suite exercised a different execution path from the
# build. kst_path_forbidden returns 1 for a clean path, so inside the offender
# loop that first non-zero return aborted the recipe under set -e and the build
# died with no diagnostic at all -- while every assertion here passed. Any gate
# exercised only in condition context is not the code the build runs.
gate_status()
{
	( set -e; check_source_tree_pure "$1" ) >/dev/null 2>&1
}

# reject DESCRIPTION -- the tree in $test_root/t must be refused
reject()
{
	_desc=$1
	if gate_status "$test_root/t"; then
		no "CONTAMINATED tree was ACCEPTED: $_desc"
	else
		ok "rejected: $_desc"
	fi
}

accept()
{
	if gate_status "$test_root/t"; then
		ok "accepted: $1"
	else
		no "a legitimate source tree was REJECTED: $1"
		# Name what it objected to: a false positive is a bug in the gate,
		# and the reader needs the offending path, not just a verdict.
		check_source_tree_pure "$test_root/t" 2>&1 | sed 's/^/         /' >&2 || true
	fi
}

# ============================================================== positive cases

make_clean "$test_root/t"
accept "a clean source tree with upstream's ambiguous-looking files"

# The BTF skeleton is a bare upstream 'vmlinux'. It is allowed by exact path.
make_clean "$test_root/t"
mkdir -p "$test_root/t/tools/perf/util/bpf_skel"
: >"$test_root/t/tools/perf/util/bpf_skel/vmlinux"
accept "the committed BTF skeleton tools/perf/util/bpf_skel/vmlinux"

# ...and a bare vmlinux anywhere else is the linked image.
make_clean "$test_root/t"
: >"$test_root/t/vmlinux"
reject "a linked vmlinux at the tree root"

make_clean "$test_root/t"
mkdir -p "$test_root/t/arch/x86/boot/compressed"
: >"$test_root/t/arch/x86/boot/compressed/vmlinux"
reject "a linked vmlinux under arch/x86/boot/compressed"

# ====================================================== the named required set
# These are the seven the task names explicitly: Module.symvers, vmlinux*,
# .config, include/generated, *.o, *.ko.

make_clean "$test_root/t"; : >"$test_root/t/Module.symvers"
reject "Module.symvers"

make_clean "$test_root/t"; : >"$test_root/t/.config"
reject ".config"

make_clean "$test_root/t"; : >"$test_root/t/vmlinux.unstripped"
reject "vmlinux.unstripped"

make_clean "$test_root/t"
mkdir -p "$test_root/t/arch/x86/boot/compressed"
: >"$test_root/t/arch/x86/boot/compressed/vmlinux.bin"
: >"$test_root/t/arch/x86/boot/compressed/vmlinux.bin.bz2"
: >"$test_root/t/arch/x86/boot/compressed/vmlinux.relocs"
reject "arch/x86/boot/compressed/vmlinux* output"

make_clean "$test_root/t"
mkdir -p "$test_root/t/arch/x86/boot" "$test_root/t/arch/x86_64/boot"
: >"$test_root/t/arch/x86/boot/bzImage"
: >"$test_root/t/arch/x86_64/boot/bzImage"
reject "arch/*/boot/bzImage"

make_clean "$test_root/t"
mkdir -p "$test_root/t/include/generated/uapi/linux"
: >"$test_root/t/include/generated/uapi/linux/version.h"
: >"$test_root/t/include/generated/autoconf.h"
reject "include/generated/"

make_clean "$test_root/t"
mkdir -p "$test_root/t/include/config"
: >"$test_root/t/include/config/kernel.release"
: >"$test_root/t/include/config/64BIT"
reject "include/config/"

make_clean "$test_root/t"
mkdir -p "$test_root/t/arch/x86/include/generated/asm"
: >"$test_root/t/arch/x86/include/generated/asm/cpufeaturemasks.h"
: >"$test_root/t/arch/x86/include/generated/asm/orc_hash.h"
reject "arch/x86/include/generated/"

make_clean "$test_root/t"
mkdir -p "$test_root/t/drivers/foo"
: >"$test_root/t/drivers/foo/thing.o"
reject "a *.o object"

make_clean "$test_root/t"
mkdir -p "$test_root/t/drivers/foo"
: >"$test_root/t/drivers/foo/thing.ko"
reject "a *.ko module"

make_clean "$test_root/t"
mkdir -p "$test_root/t/lib"
: >"$test_root/t/lib/lib.a"
reject "a build-generated lib.a"

# ================================================ the rest of the r1 payload class

make_clean "$test_root/t"
mkdir -p "$test_root/t/scripts/mod"
: >"$test_root/t/scripts/mod/modpost"
: >"$test_root/t/scripts/sign-file"
mkdir -p "$test_root/t/tools/objtool"
: >"$test_root/t/tools/objtool/fixdep"
: >"$test_root/t/tools/objtool/objtool"
: >"$test_root/t/scripts/kconfig/conf"
reject "built host tools (modpost, sign-file, fixdep, objtool, conf)"

make_clean "$test_root/t"; : >"$test_root/t/.tmp_missing-syscalls"
reject "the .tmp_missing-syscalls build stamp"

make_clean "$test_root/t"; mkdir -p "$test_root/t/security"; : >"$test_root/t/security/modules.order"
reject "an install-time modules.order"

make_clean "$test_root/t"; mkdir -p "$test_root/t/certs"; : >"$test_root/t/certs/module-signing.pem"
reject "module signing key material"

make_clean "$test_root/t"
mkdir -p "$test_root/t/kernel"
: >"$test_root/t/kernel/config_data"
: >"$test_root/t/kernel/kheaders.md5"
: >"$test_root/t/kernel/kheaders_data.tar.xz"
reject "kheaders/config build products"

make_clean "$test_root/t"
mkdir -p "$test_root/t/arch/x86/boot/compressed"
: >"$test_root/t/arch/x86/boot/compressed/piggy.S"
: >"$test_root/t/arch/x86/boot/compressed/vmlinux.lds"
reject "the compressed-kernel intermediate piggy.S"

# A generated DIRECTORY with nothing inside it is still a defect.
make_clean "$test_root/t"; mkdir -p "$test_root/t/include/generated"
reject "an EMPTY include/generated/ directory" "empty include/generated"

make_clean "$test_root/t"; mkdir -p "$test_root/t/certs/regdb"
reject "a certs/regdb/ directory (the recipe must never create one)"

# A clean tree must not merely report OK: it must SURVIVE being called the way
# the recipe calls it, bare, under set -e. This is the assertion that would
# have caught the aborted-build defect above, and it is deliberately a separate
# case from the `accept` assertions.
#
# Both halves run under `set -euo pipefail`, because that is what
# buildpkg-single sets, and both bugs found here were invisible without it.
make_clean "$test_root/t"
if ( set -euo pipefail; check_source_tree_pure "$test_root/t" ) >/dev/null 2>&1; then
	ok "a clean tree returns 0 under a bare set -euo pipefail call"
else
	no "a clean tree aborted or failed under a bare set -euo pipefail call - the gate is unusable from a recipe"
fi

# And the contaminated case must still fail closed through that same path, with
# the intended status 1 and not 141. A tree with far more offenders than the
# gate prints makes `head` close the pipe early; under pipefail that SIGPIPE
# surfaces as 141, which turns "the gate found contamination" into "the gate
# crashed" and hides the whole point.
make_clean "$test_root/t"
i=0
while [ "$i" -lt 200 ]; do
	mkdir -p "$test_root/t/include/generated"
	: >"$test_root/t/include/generated/gen$i.h"
	i=$((i + 1))
done
# rc=0 || rc=$? -- capture the status without tripping this suite's own set -e
# on the very failure it is asserting.
rc=0
( set -euo pipefail; check_source_tree_pure "$test_root/t" ) >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 1 ]; then
	ok "a heavily contaminated tree fails with status 1, not 141 (no SIGPIPE leak)"
elif [ "$rc" -eq 141 ]; then
	no "a heavily contaminated tree exits 141 - the diagnostic pipeline leaks SIGPIPE under pipefail"
else
	no "a heavily contaminated tree exited $rc, expected 1"
fi

# ================================================ install_clean_source_tree

# A clean input stages and the destination is clean.
make_clean "$test_root/src"
make_clean "$test_root/dest"
if install_clean_source_tree "$test_root/src" "$test_root/dest" >/dev/null 2>&1; then
	if [ -f "$test_root/dest/Makefile" ]; then
		ok "install_clean_source_tree stages a clean tree"
	else
		no "install_clean_source_tree reported success but staged no Makefile"
	fi
else
	no "install_clean_source_tree refused a clean source tree"
fi

# An in-tree symlink survives the copy.
if [ -L "$test_root/dest/arch-link" ]; then
	ok "install_clean_source_tree preserves in-tree symlinks"
else
	no "install_clean_source_tree did not preserve an in-tree symlink"
fi

# A contaminated input must be refused BEFORE anything is staged, so the bad
# path never reaches the payload at all.
make_clean "$test_root/src"; mkdir -p "$test_root/src/include/generated"
: >"$test_root/src/include/generated/autoconf.h"
rm -rf "$test_root/dest"; mkdir -p "$test_root/dest"
if install_clean_source_tree "$test_root/src" "$test_root/dest" >/dev/null 2>&1; then
	no "install_clean_source_tree ACCEPTED a contaminated source tree"
else
	if [ -z "$(ls -A "$test_root/dest" 2>/dev/null)" ]; then
		ok "a contaminated input is refused with nothing staged"
	else
		no "a contaminated input was refused but files were staged anyway"
	fi
fi

# A missing Makefile is not a kernel tree.
rm -rf "$test_root/src"; mkdir -p "$test_root/src"
if check_source_tree_pure "$test_root/src" >/dev/null 2>&1; then
	no "a directory with no Makefile was accepted as a kernel source tree"
else
	ok "a directory with no Makefile is rejected"
fi

# A non-existent tree is an error, not an empty pass.
if check_source_tree_pure "$test_root/does-not-exist" >/dev/null 2>&1; then
	no "a missing tree was ACCEPTED"
else
	ok "a missing tree is rejected"
fi

# Wrong arity is refused rather than silently accepted.
if check_source_tree_pure "$test_root/src" extra >/dev/null 2>&1; then
	no "a wrong-arity call was ACCEPTED"
else
	ok "a wrong-arity call is refused"
fi

if install_clean_source_tree "$test_root/src" >/dev/null 2>&1; then
	no "a wrong-arity install_clean_source_tree call was ACCEPTED"
else
	ok "a wrong-arity install_clean_source_tree call is refused"
fi

printf 'kernel-source-tree: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]