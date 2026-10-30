#!/bin/sh

# saphira-earlyfw: per-kernel early-firmware boot images.
#
# Rootless suite (same contract as initramfs.sh): a fake target root
# with sysfs PCI entries, firmware dirs and a modules directory
# exercises selection, packing, pruning and every refusal, with no
# loop device, no mount and no GRUB.
#
# usage: earlyfw.sh [TOOLS-ROOT]
#
#   TOOLS-ROOT is a root containing an installed saphira-earlyfw, i.e.
#   $TOOLS-ROOT/usr/sbin/saphira-earlyfw. Defaults to /usr.

set -eu

tools=${1:-/usr}

earlyfw=$tools/usr/sbin/saphira-earlyfw

fail() {
	printf 'earlyfw: %s\n' "$*" >&2
	exit 1
}

[ -x "$earlyfw" ] || fail "generator not executable: $earlyfw"
command -v cpio >/dev/null 2>&1 || fail 'cpio not on PATH'
command -v zstd >/dev/null 2>&1 || fail 'zstd not on PATH'

scratch=${SAPHIRA_TMPDIR:-/build/tmp}
mkdir -p "$scratch" || fail "cannot create scratch under $scratch"
work=$(mktemp -d "$scratch/earlyfw-test.XXXXXX") ||
	fail 'cannot create a work directory'
trap 'rm -rf -- "$work"' EXIT HUP INT TERM

SAPHIRA_TMPDIR=$work
export SAPHIRA_TMPDIR

checks=0
ok() {
	checks=$((checks + 1))
	printf '  ok   %s\n' "$1"
}

refused() {
	description=$1
	shift
	if "$@" >"$work/out" 2>&1; then
		printf 'earlyfw: expected a refusal: %s\n' "$description" >&2
		sed 's/^/    /' "$work/out" >&2
		exit 1
	fi
	[ -s "$work/out" ] || {
		printf 'earlyfw: refused %s but said nothing\n' "$description" >&2
		exit 1
	}
}

# Fake target root: Alder Lake iGPU + one kernel + i915 blobs.
fakeroot() {
	root=$work/root
	rm -rf -- "$root"
	mkdir -p "$root/sys/bus/pci/devices/0000:00:02.0" \
		"$root/lib/firmware/i915" \
		"$root/lib/modules/7.2.3-test" \
		"$root/boot"
	printf '0x8086\n' > "$root/sys/bus/pci/devices/0000:00:02.0/vendor"
	printf '0x46d1\n' > "$root/sys/bus/pci/devices/0000:00:02.0/device"
	printf '0x030000\n' > "$root/sys/bus/pci/devices/0000:00:02.0/class"
	printf 'guc-bytes\n' > "$root/lib/firmware/i915/tgl_guc_70.bin"
	printf 'dmc-bytes\n' > "$root/lib/firmware/i915/adlp_dmc.bin"
	printf 'include i915\n' > "$work/earlyfw.conf"
	printf '0x8086 0x03 require i915 linux-firmware-i915\n' > "$work/pci.map"
	printf '0x1002 0x03 optional amdgpu linux-firmware-amd\n' >> "$work/pci.map"
}

export SAPHIRA_EARLYFW_MAP=$work/pci.map
export SAPHIRA_EARLYFW_CONF=$work/earlyfw.conf

# 1. Intel PCI selects i915; image carries the blobs; grub untouched
#    for a foreign root.
fakeroot
"$earlyfw" --all --root "$work/root" --boot "$work/root/boot" \
	>"$work/out" 2>&1 || fail 'build failed'
[ -f "$work/root/boot/earlyfw-7.2.3-test.img" ] ||
	fail 'per-release image missing'
zstd -dc -- "$work/root/boot/earlyfw-7.2.3-test.img" |
	cpio -it --quiet 2>/dev/null > "$work/listing" ||
	fail 'image does not parse'
grep -qx 'lib/firmware/i915/tgl_guc_70.bin' "$work/listing" ||
	fail 'GuC blob missing from image'
grep -qx 'lib/firmware/i915/adlp_dmc.bin' "$work/listing" ||
	fail 'DMC blob missing from image'
if grep -q '/init$' "$work/listing"; then
	fail 'firmware image must not carry /init'
fi
ok 'intel PCI selects i915 firmware, no /init takeover'

# 2. Required-but-missing firmware fails LOUD (never a silent wedge).
fakeroot
rm -rf -- "$work/root/lib/firmware/i915"
refused 'missing required i915' \
	"$earlyfw" --all --root "$work/root" --boot "$work/root/boot"
ok 'missing required firmware is fatal'

# 3. Failed build leaves the previous image byte-identical.
fakeroot
"$earlyfw" --all --root "$work/root" --boot "$work/root/boot" \
	>"$work/out" 2>&1 || fail 'baseline build failed'
sha256sum "$work/root/boot/earlyfw-7.2.3-test.img" > "$work/before"
rm -rf -- "$work/root/lib/firmware/i915"
refused 'second build with firmware removed' \
	"$earlyfw" --all --root "$work/root" --boot "$work/root/boot"
sha256sum -c "$work/before" >/dev/null 2>&1 ||
	fail 'previous image not preserved across failure'
ok 'atomic replace: failure keeps the previous image'

# 4. Stale per-release images are pruned, both name generations.
fakeroot
touch -- "$work/root/boot/earlyfw-9.9.9-gone.img"
touch -- "$work/root/boot/initramfs-9.9.9-gone.img"
"$earlyfw" --all --root "$work/root" --boot "$work/root/boot" \
	>"$work/out" 2>&1 || fail 'prune build failed'
[ ! -e "$work/root/boot/earlyfw-9.9.9-gone.img" ] ||
	fail 'stale image not pruned'
[ ! -e "$work/root/boot/initramfs-9.9.9-gone.img" ] ||
	fail 'stale legacy image not pruned'
[ -f "$work/root/boot/earlyfw-7.2.3-test.img" ] ||
	fail 'live image pruned by mistake'
ok 'stale images pruned, live images kept'

# 5. AMD microcode assembles when blobs are present (audit path).
fakeroot
mkdir -p "$work/root/lib/firmware/amd-ucode"
printf 'amd-bytes-1' > "$work/root/lib/firmware/amd-ucode/microcode_amd.bin"
printf 'amd-bytes-2' > "$work/root/lib/firmware/amd-ucode/microcode_amd_fam19h.bin"
"$earlyfw" --all --root "$work/root" --boot "$work/root/boot" \
	>"$work/out" 2>&1 || fail 'amd build failed'
[ -f "$work/root/boot/amd-ucode.img" ] || fail 'amd-ucode.img missing'
cpio -it --quiet < "$work/root/boot/amd-ucode.img" > "$work/amdlisting" 2>/dev/null ||
	fail 'amd image does not parse'
grep -qx 'kernel/x86/microcode/AuthenticAMD.bin' "$work/amdlisting" ||
	fail 'AuthenticAMD.bin missing from amd image'
ok 'amd microcode assembles from installed blobs'

# 6. No AMD blobs, no amd image (and no failure).
fakeroot
"$earlyfw" --all --root "$work/root" --boot "$work/root/boot" \
	>"$work/out" 2>&1 || fail 'no-amd build failed'
[ ! -e "$work/root/boot/amd-ucode.img" ] ||
	fail 'amd image built without blobs'
ok 'absent amd blobs skip quietly'

# 7. Optional-but-missing map hardware is a notice, not fatal.
fakeroot
mkdir -p "$work/root/sys/bus/pci/devices/0000:03:00.0"
printf '0x1002\n' > "$work/root/sys/bus/pci/devices/0000:03:00.0/vendor"
printf '0x030000\n' > "$work/root/sys/bus/pci/devices/0000:03:00.0/class"
"$earlyfw" --all --root "$work/root" --boot "$work/root/boot" \
	>"$work/out" 2>&1 || fail 'optional-hardware build failed'
grep -q 'optional amdgpu absent' "$work/out" ||
	fail 'optional skip not reported'
ok 'driverless hardware skips with notice'

printf 'earlyfw: OK (%s checks)\n' "$checks"
