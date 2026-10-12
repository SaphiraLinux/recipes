#!/bin/sh

# staged-kernel provenance gate.
#
# stage-kmod-input.sh decides which kernel tree external modules may be built
# against. It used to decide on directory name, tree contents, and the
# existence of a built scripts/sign-file -- none of which identify WHICH
# kernel a tree belongs to. A tree left over from an older pkgrel therefore
# looked perfectly kmod-ready, and on this host two of them were.
#
# The reason that matters is CONFIG_MODVERSIONS being unset. Without symbol
# CRCs, vermagic is only the upstream version, so a module built against the
# wrong tree does not fail to load -- it loads, and is wrong quietly. The stale
# 7.2.2 tree differed from the published config in 60 keys, among them
# CRYPTO_CMAC / CRYPTO_SHA1 / CRYPTO_SHA512 / CRYPTO_LZ4 moving y->m, which
# changes which symbols are exported to modules at all, plus PREFIX_SYMBOLS
# and BPF_LSM appearing on one side only, and a different
# CONFIG_MODULE_SIG_KEY. Nothing in the loader would ever have said so.
#
# The gate now requires a tree's .config to equal the PUBLISHED kernel's
# /boot/config-<kver>-akadata, compared as effective order-independent
# settings, plus a matching kernel.release. It must never be weakened to a
# pkgrel, timestamp, directory-name or vermagic check: all four of those
# survive a pkgrel bump unchanged, which is exactly the bug.
#
# Roots are redirected to fixtures so this suite is hermetic; the real script
# defaults to /usr/src and /boot. The accepted case is bind-mounted, so sudo is
# needed for that one case, as it is for real staging.

set -eu

[ "$#" -eq 1 ] || {
	printf 'usage: %s STAGE-KMOD-INPUT\n' "$0" >&2
	exit 1
}
stager=$1

SAPHIRA_TMPDIR=${SAPHIRA_TMPDIR:-/build/tmp}
work=$SAPHIRA_TMPDIR/kmod-provenance
sudo -n rm -rf "$work" 2>/dev/null || rm -rf "$work" 2>/dev/null || true
mkdir -p "$work/src" "$work/boot" "$work/out"
trap 'sudo -n umount "$work"/out/linux-* 2>/dev/null || true; sudo -n rm -rf "$work" 2>/dev/null || rm -rf "$work" 2>/dev/null || true' EXIT

pass=0
fail=0
ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
no() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

KVER=7.2.2

# A tree that satisfies the readiness gate: Makefile, built sign-file, config,
# release, and a real .config.
make_tree()
{
	_dest=$1
	release=$2
	config=$3
	mkdir -p "$_dest"
	printf 'obj-m += zfs\n' >"$_dest/Makefile"
	mkdir -p "$_dest/scripts"
	printf '#!/bin/sh\nexit 0\n' >"$_dest/scripts/sign-file"
	chmod +x "$_dest/scripts/sign-file"
	mkdir -p "$_dest/include/config"
	printf '%s\n' "$release" >"$_dest/include/config/kernel.release"
	cp "$config" "$_dest/.config"
}

# The published config the gate compares against. Deliberately carries the
# Phase K settings, because those are exactly what a stale tree lacks.
published=$work/boot/config-$KVER-akadata
cat >"$published" <<'EOF'
CONFIG_BLK_DEV_INITRD=y
CONFIG_RD_ZSTD=y
CONFIG_MODULES=y
CONFIG_MODULE_UNLOAD=y
CONFIG_MODULE_SIG=y
CONFIG_CRYPTO_CMAC=m
EOF

# A stale pre-Phase-K config: same kernel VERSION, different contents. This is
# the historical reproducer and the case that must never be accepted.
stale_cfg=$work/stale.config
cat >"$stale_cfg" <<'EOF'
# CONFIG_BLK_DEV_INITRD is not set
CONFIG_MODULES=y
CONFIG_MODULE_UNLOAD=y
CONFIG_MODULE_SIG=y
CONFIG_CRYPTO_CMAC=y
EOF

# Run the gate over a fixture src root, report what it staged.
run_gate()
{
	rm -rf "$work/out"
	mkdir -p "$work/out"
	SAPHIRA_KMOD_SRC_ROOT=$1 SAPHIRA_KMOD_BOOT_ROOT=$work/boot \
		"$stager" "$work/out" 2>&1 || true
}

# ---------------------------------------------------------- reject: wrong cfg
# Same kernel version, wrong .config. Must be rejected even though the
# directory is named for the right kernel, the Makefile and sign-file are
# present, and kernel.release matches exactly.
make_tree "$work/src/linux-$KVER-saphira" "$KVER" "$stale_cfg"
out=$(run_gate "$work/src")
case $out in
*"skipped kernel tree $KVER(config-not-published-$KVER)"*)
	ok "same version + wrong .config -> REJECT (historical reproducer)" ;;
*)
	no "same version + wrong .config was not rejected [got: $out]" ;;
esac
if [ -z "$(ls -A "$work/out" 2>/dev/null)" ]; then
	ok "wrong-config tree is not staged"
else
	no "wrong-config tree was staged: $(ls -A "$work/out")"
fi

# ------------------------------------------- reject: right config, wrong rel
# Config matches the published config exactly, but the tree says it is a
# different kernel release. Release alone is not identity either.
make_tree "$work/src/linux-$KVER-saphira" "7.2.2-akadata-mismatch" "$published"
out=$(run_gate "$work/src")
case $out in
*"skipped kernel tree $KVER"*)
	ok "matching config + wrong kernel.release -> REJECT" ;;
*)
	no "wrong kernel.release was not rejected [got: $out]" ;;
esac
if [ -z "$(ls -A "$work/out" 2>/dev/null)" ]; then
	ok "wrong-release tree is not staged"
else
	no "wrong-release tree was staged: $(ls -A "$work/out")"
fi

# ------------------------------------------- reject: stale plain-named tree
# A plain /usr/src/linux-7.2.2 (no -saphira suffix) with a stale config: the
# exact shape found on the host, which the old gate accepted.
sudo -n rm -rf "$work/src" 2>/dev/null || rm -rf "$work/src"
mkdir -p "$work/src"
make_tree "$work/src/linux-$KVER" "$KVER" "$stale_cfg"
out=$(run_gate "$work/src")
case $out in
*"skipped kernel tree $KVER(config-not-published-$KVER)"*)
	ok "stale plain /usr/src/linux-$KVER tree -> REJECT" ;;
*)
	no "stale plain tree was not rejected [got: $out]" ;;
esac

# ------------------------------------------------- accept: correct r9 tree
# Config identical to the published config, release identical, and it is the
# -saphira prepared tree. This one must be staged.
sudo -n rm -rf "$work/src" 2>/dev/null || rm -rf "$work/src"
mkdir -p "$work/src"
make_tree "$work/src/linux-$KVER-saphira" "$KVER" "$published"
out=$(run_gate "$work/src")
if ls -d "$work/out/linux-$KVER" >/dev/null 2>&1; then
	ok "published prepared tree (config + release match) -> ACCEPT"
	sudo -n umount "$work/out/linux-$KVER" 2>/dev/null || true
else
	no "correct published prepared tree was not staged [got: $out]"
fi

# ---------------------------------------- the gate must not be a name check
# Guard the specific weakening that would reintroduce the original bug: a
# same-version tree whose only problem is a stale config must never be let
# through by a pkgrel, mtime, directory-name or vermagic shortcut.
sudo -n rm -rf "$work/src" 2>/dev/null || rm -rf "$work/src"
mkdir -p "$work/src"
make_tree "$work/src/linux-$KVER-saphira" "$KVER" "$stale_cfg"
# Make it look as authoritative as possible by every shortcut that must not be
# relied on: a fresh mtime, and a name that matches the published kernel.
touch "$work/src/linux-$KVER-saphira" "$work/src/linux-$KVER-saphira/.config"
stager_code=$(sed -e 's/[[:space:]]*#.*$//' "$stager")
shortcut='pkgrel|mtime|newer|vermagic|symlink.*-name'
if printf '%s\n' "$stager_code" | grep -qE "$shortcut"; then
	no "stager code references a pkgrel/mtime/newer/vermagic identity shortcut"
else
	ok "stager code uses no pkgrel/mtime/newer/vermagic identity shortcut"
fi
if grep -q 'kernel.release' "$stager"; then
	ok "stager compares kernel.release"
else
	no "stager does not compare kernel.release"
fi
if grep -qE 'CONFIG_|effective_settings|\.config' "$stager"; then
	ok "stager compares .config contents"
else
	no "stager does not compare .config contents"
fi

printf 'kmod provenance gate: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
