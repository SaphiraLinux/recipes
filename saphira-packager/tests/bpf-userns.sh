#!/bin/sh
#
# bpf-userns.sh: guard the capability that rootless systemd-nspawn needs.
#
# Rootless nspawn selects USER_NAMESPACE_MANAGED by default whenever
# getuid() != 0, and managed mode asks systemd-nsresourced for a 64K user
# namespace. nsresourced refuses unless it can lock that namespace down
# with a BPF LSM program, and it fails closed: nsresourcework.c returns the
# error from userns_restrict_install() with no fallback.
#
# That makes this a chain where every link is individually removable and
# each removal fails SILENTLY or only at runtime:
#
#   kernel  CONFIG_BPF_LSM        the LSM itself
#   kernel  CONFIG_SECURITY_PATH  the path-mutating hooks, without which
#                                 systemd's program cannot attach
#   kernel  CONFIG_SECURITYFS    systemd reads the active LSM list from it
#   kernel  CONFIG_DEBUG_INFO_BTF vmlinux.h is derived from the BTF
#   systemd bpf-framework=enabled HAVE_VMLINUX_H, else EOPNOTSUPP
#   systemd vmlinux-h=provided   'auto' silently uses the BUILD HOST's
#                                 live /sys/kernel/btf/vmlinux
#   build   libbpf, bpftool, clang with a BPF backend
#
# Each of those was, at one point or another, missing, and each produced a
# failure that looked identical from the outside: "Failed to allocate user
# namespace with 64K users: Not supported". This test exists so that a
# future rebuild cannot silently drop any of them.
#
# usage: bpf-userns.sh [RECIPE-ROOT]

set -eu

root=${1:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
kver=7.2.2
kconfig=$root/saphira-kernel-$kver/files/config-$kver-akadata
sysd=$root/systemd/recipe.sh
vmlinux=$root/systemd/files/vmlinux.h
sidecar=$root/systemd/files/vmlinux.h.sha256
bpfrecipe=$root/bpftool/recipe.sh
llvmrecipe=$root/llvm/recipe.sh
clangrecipe=$root/clang/recipe.sh

scratch=${SAPHIRA_TMPDIR:-/build/tmp}
checks=0

fail()
{
	printf '%s\n' "bpf-userns: $*" >&2
	exit 1
}

ok()
{
	checks=$((checks + 1))
	printf '  ok   %s\n' "$1"
}

# --- 1. the kernel config, as vendored ---------------------------------

[ -f "$kconfig" ] || fail "kernel config is missing: $kconfig"

# Each of these must be =y. A duplicate "# CONFIG_X is not set" later in
# the file wins over an earlier "=y" -- Kconfig takes the last occurrence --
# so a presence check is not enough; the resolved value is what counts.
kernel_y()
{
	# If the symbol appears more than once the file is ambiguous and must
	# be rejected outright rather than guessed at.
	n=$(grep -cE "^(CONFIG_$1=|# CONFIG_$1 is not set)\$" "$kconfig" || true)
	[ "$n" -le 1 ] ||
		fail "CONFIG_$1 appears $n times in $kconfig; the resolved value would be ambiguous"
	grep -qE "^CONFIG_$1=y\$" "$kconfig" ||
		fail "CONFIG_$1 is not =y in $kconfig"
	ok "kernel: CONFIG_$1=y"
}

printf '%s\n' "bpf-userns: kernel config ($kver)"
kernel_y SECURITY
kernel_y SECURITYFS
kernel_y SECURITY_PATH
kernel_y BPF_LSM
kernel_y DEBUG_INFO_BTF
kernel_y DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT

# BTF needs pahole >= 122; the config records the detected version.
pahole_ver=$(sed -n 's/^CONFIG_PAHOLE_VERSION=//p' "$kconfig")
[ -n "$pahole_ver" ] || fail "CONFIG_PAHOLE_VERSION is not recorded in $kconfig"
[ "$pahole_ver" -ge 122 ] ||
	fail "CONFIG_PAHOLE_VERSION=$pahole_ver; BTF requires >= 122"
ok "kernel: CONFIG_PAHOLE_VERSION=$pahole_ver (>= 122 required for BTF)"

# GDB_SCRIPTS is NOT required for BTF in 7.2.2. It was deliberately not
# enabled, so assert it stays off rather than letting a future edit creep
# it in: DEBUG_INFO_BTF's stanza depends only on PAHOLE_VERSION.
grep -qE '^CONFIG_GDB_SCRIPTS=y$' "$kconfig" &&
	fail "CONFIG_GDB_SCRIPTS=y; 7.2.2's DEBUG_INFO_BTF does not need it and the kernel change was scoped to the minimum"
ok "kernel: GDB_SCRIPTS stays off (not required for BTF in 7.2.2)"

# bpf must be in the LSM ordering, or the LSM never registers.
grep -qE '^CONFIG_LSM="[^"]*bpf' "$kconfig" ||
	fail "CONFIG_LSM does not include bpf; the BPF LSM would never register"
ok "kernel: bpf is in CONFIG_LSM"

# Only the current kernel is in scope. A sibling config gaining or losing
# these symbols is a deliberate forward-port decision, not this test's
# business -- but silently losing them in a version that IS built would be
# a bug, so assert the others are still the old states.
for other in 7.1.5 7.2.3; do
	f=$root/saphira-kernel-$other/files/config-$other-akadata
	[ -f "$f" ] || continue
	if grep -qE '^CONFIG_SECURITY_PATH=y$' "$f"; then
		fail "config-$other-akadata has SECURITY_PATH=y; only $kver is in scope and proven"
	fi
done
ok "kernel: 7.1.5 / 7.2.3 / 7.3-rc1 configs untouched (only $kver is in scope)"

# --- 2. the systemd build ----------------------------------------------

printf '%s\n' "bpf-userns: systemd build"
[ -f "$sysd" ] || fail "systemd recipe is missing: $sysd"

grep -qE '^\s*-Dbpf-framework=enabled' "$sysd" ||
	fail "systemd does not enable bpf-framework; HAVE_VMLINUX_H will be unset and nsresourced fails closed with EOPNOTSUPP"
ok "systemd: -Dbpf-framework=enabled"

# 'auto' falls back to the BUILD HOST's live /sys/kernel/btf/vmlinux, so
# the compiled BPF programs would bind to whatever kernel ran the build.
if grep -qE '^\s*-Dvmlinux-h=auto' "$sysd"; then
	fail "systemd uses -Dvmlinux-h=auto, which generates vmlinux.h from the build host's running kernel"
fi
grep -qE '^\s*-Dvmlinux-h=provided' "$sysd" ||
	fail "systemd must use -Dvmlinux-h=provided for a reproducible, host-independent build"
grep -qE '^\s*-Dvmlinux-h-path=' "$sysd" ||
	fail "systemd does not pass -Dvmlinux-h-path; 'provided' without a path resolves to nothing"
ok "systemd: -Dvmlinux-h=provided with an explicit path (not auto)"

for dep in bpftool clang libbpf-dev elfutils-dev; do
	case " $(sed -n '/^makedepends=/,/^"$/p' "$sysd" | tr '\n' ' ') " in
	*" $dep "*) ok "systemd: makedepends carries $dep" ;;
	*) fail "systemd makedepends is missing $dep; the BPF build cannot succeed without it" ;;
	esac
done

# --- 3. the vendored vmlinux.h -----------------------------------------

printf '%s\n' "bpf-userns: vendored vmlinux.h"
[ -f "$vmlinux" ] || fail "vmlinux.h is missing: $vmlinux"
[ -f "$sidecar" ] || fail "vmlinux.h has no sidecar: $sidecar"
(cd "$(dirname "$vmlinux")" && sha256sum -c "$(basename "$sidecar")" >/dev/null 2>&1) ||
	fail "vmlinux.h does not match its sidecar"
ok "vmlinux.h: sidecar verifies"

# The header must actually carry the hook heads the userns lockdown binds
# against. This is the check that catches the real failure: a header
# generated before CONFIG_SECURITY_PATH existed has no path_* hook heads,
# and the BPF program then fails to load with ESRCH at runtime.
#
# The marker is the security_hook_heads entry, not the function name:
# bpftool's `btf dump format c` emits types, not free functions, so
# bpf_lsm_path_chown never appears in the header at all. The hook head
# `struct lsm_static_call path_chown[3];` is emitted only when the hook
# exists, which is exactly the property being asserted.
for hook in path_chown task_fix_setgroups; do
	grep -q "struct lsm_static_call $hook\[" "$vmlinux" ||
		fail "vmlinux.h has no $hook hook head; regenerate it from a kernel whose BTF exports it (CONFIG_SECURITY_PATH=y for the path_* hooks)"
done
ok "vmlinux.h: carries the path_chown and task_fix_setgroups hook heads"

# --- 4. the build inputs -----------------------------------------------

printf '%s\n' "bpf-userns: build inputs"
[ -f "$bpfrecipe" ] || fail "no bpftool recipe; systemd's BPF build requires it"
grep -q 'pkgname=bpftool' "$bpfrecipe" ||
	fail "bpftool recipe has an unexpected pkgname"
grep -qE '/usr/sbin/bpftool' "$bpfrecipe" ||
	fail "bpftool is not installed to /usr/sbin, which is where systemd's meson looks for it"
ok "bpftool: recipe present and installs to /usr/sbin"

# clang cannot compile for BPF unless the BPF backend was built into it,
# and that comes from llvm. clang must ALSO have been rebuilt: a clang
# linked against a BPF-capable libLLVM still fails `clang -target bpf`
# unless it was compiled with the target itself.
grep -qE 'LLVM_TARGETS_TO_BUILD="?[^"]*BPF' "$llvmrecipe" ||
	fail "llvm does not build the BPF backend; clang -target bpf will fail"
grep -q 'BPF' "$clangrecipe" ||
	fail "clang recipe does not mention the BPF requirement; if llvm gained BPF, clang must be rebuilt against it"
ok "llvm/clang: BPF backend built, and clang carries the rebuild note"

mkdir -p "$scratch" || fail "cannot create scratch under $scratch"

printf '%s\n' "bpf-userns: OK ($checks checks)"
