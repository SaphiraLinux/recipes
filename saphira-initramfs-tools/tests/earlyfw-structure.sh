#!/bin/sh

# saphira-earlyfw structure tests: the firmware-only boot image the
# kernel's early filesystem lookup consumes for built-in drivers.
#
# What MUST hold (kernel side, running config BLK_DEV_INITRD=y with an
# RD_* decompressor and FW_LOADER=y, EXTRA_FIRMWARE empty):
#   - one zstd frame decompressing to exactly one newc cpio archive
#     (TRAILER!!! present, zero-padded tail, no trailing archive);
#   - every entry root-relative under lib/firmware/ (the loader's
#     canonical paths); no /init (this is NOT an initramfs and must
#     never become one), no device nodes, no absolute symlinks;
#   - ownership 0:0, pinned mtimes, byte-identical rebuilds;
#   - required-but-missing firmware refuses loudly instead of
#     producing an image a built-in driver would wedge on;
#   - nothing is written outside --boot, and grub.cfg is regenerated
#     only for the live root (offline runs stay offline).
#
# Hermetic: fixture sysroot + fixture PCI sysfs + fixture map/conf
# under SAPHIRA_TMPDIR. Touches no live root, no /boot, no grub.
# Never runs against / (pass a fixture --root; the generator itself
# refuses grub regeneration for non-live roots).
#
# usage: earlyfw-structure.sh SAPhIRA-EARLYFW
#
#   SAPhIRA-EARLYFW is the generator under test (an installed
#   /usr/sbin/saphira-earlyfw, or a scratch-extracted package copy -
#   never run a generator against the live root from here).

set -eu

[ "$#" -eq 1 ] || {
	printf 'usage: %s SAPhIRA-EARLYFW\n' "$0" >&2
	exit 1
}

earlyfw=$1
[ -r "$earlyfw" ] || {
	printf 'earlyfw-structure: generator not readable: %s\n' "$earlyfw" >&2
	exit 1
}
# Driven through sh so the suite does not depend on the source
# tree's execute bit; the installed artifact is always 0755.
run_earlyfw() {
	sh "$earlyfw" "$@"
}

for tool in cpio zstd sort awk; do
	command -v "$tool" >/dev/null 2>&1 || {
		printf 'earlyfw-structure: missing host tool: %s\n' "$tool" >&2
		exit 1
	}
done

test_tmp_base=${SAPHIRA_TMPDIR:-/build/tmp}
mkdir -p "$test_tmp_base"
test_root=$(mktemp -d "$test_tmp_base/saphira-earlyfw-test.XXXXXX")
export SAPHIRA_TMPDIR=$test_root/tool-tmp
mkdir -p "$SAPHIRA_TMPDIR"
trap 'chmod -R u+rwX "$test_root" 2>/dev/null || true; rm -rf "$test_root"' EXIT HUP INT TERM

checks=0
ok() {
	checks=$((checks + 1))
	printf '  ok   %s\n' "$1"
}
fail() {
	printf 'earlyfw-structure: %s\n' "$*" >&2
	exit 1
}

# --- fixture sysroot -------------------------------------------------
KVER=7.99.0-test
sysroot=$test_root/root
mkdir -p "$sysroot/lib/modules/$KVER" \
	"$sysroot/lib/firmware/i915pci" \
	"$sysroot/lib/firmware/i915base" \
	"$sysroot/sys/bus/pci/devices/0000:00:02.0" \
	"$sysroot/etc/saphira"
printf 'pci-blob-bytes' > "$sysroot/lib/firmware/i915pci/adlp_dmc.bin"
printf 'pci-guc-bytes' > "$sysroot/lib/firmware/i915pci/tgl_guc_70.real.bin"
ln -s tgl_guc_70.real.bin "$sysroot/lib/firmware/i915pci/tgl_guc_70.bin"
printf 'base-blob-bytes' > "$sysroot/lib/firmware/i915base/huc.bin"
printf '0x8086\n' > "$sysroot/sys/bus/pci/devices/0000:00:02.0/vendor"
printf '0x030000\n' > "$sysroot/sys/bus/pci/devices/0000:00:02.0/class"
printf '# fixture map\n0x8086 0x03 require i915pci fixture-pkg\n' > "$test_root/fixture.map"
printf 'include i915base\n' > "$test_root/fixture.conf"
export SAPHIRA_EARLYFW_MAP="$test_root/fixture.map"
export SAPHIRA_EARLYFW_CONF="$test_root/fixture.conf"
# A pinned epoch distinct from the generator default, so the test
# proves pinning rather than coinciding with it.
export SAPHIRA_SOURCE_DATE_EPOCH=1700000000

bootdir=$test_root/boot
mkdir -p "$bootdir"

run_earlyfw --all --root "$sysroot" --boot "$bootdir" \
	>"$test_root/build.out" 2>&1 ||
	{ sed 's/^/    /' "$test_root/build.out" >&2; fail 'generator failed on a good fixture'; }
img=$bootdir/earlyfw-$KVER.img
[ -f "$img" ] || fail 'no per-release image was produced'
[ -s "$img" ] || fail 'image is empty'
ok "image produced for installed release ($KVER)"

# --- frame: one zstd stream, clean decompression ---------------------
head -c 4 -- "$img" | od -A n -t x1 | grep -q '28 b5 2f fd' ||
	fail 'image has no zstd magic'
ok 'image is a zstd frame'
zstd -dc -- "$img" >"$test_root/fw.cpio" 2>/dev/null ||
	fail 'image does not decompress as zstd'
# A second decompression must agree byte-for-byte (single frame,
# no trailing garbage after the stream).
zstd -dc -- "$img" 2>/dev/null | cmp -s - "$test_root/fw.cpio" ||
	fail 'zstd stream is not a single clean frame'
ok 'exactly one clean zstd frame'

# --- archive: exactly one newc cpio ----------------------------------
head -c 6 -- "$test_root/fw.cpio" | od -A n -t x1 | grep -q '30 37 30 37 30 31' ||
	fail 'archive has no newc magic'
ok 'archive is newc cpio'
[ "$(grep -a -o 'TRAILER!!!' "$test_root/fw.cpio" | wc -l)" -eq 1 ] ||
	fail 'archive does not carry exactly one TRAILER!!!'
listing=$(cpio -it <"$test_root/fw.cpio" 2>/dev/null) ||
	fail 'generated cpio does not parse'
[ -n "$listing" ] || fail 'cpio listing is empty'
# One magic per listed entry plus the trailer, then zero padding
# only: any second archive or stray bytes change this count.
entries=$(printf '%s\n' "$listing" | grep -c .)
[ "$(grep -a -o '070701' "$test_root/fw.cpio" | wc -l)" -eq $((entries + 1)) ] ||
	fail 'archive is not exactly one cpio (unexpected header count)'
# newc headers are fixed 110 bytes; TRAILER!!! is 10 chars + NUL
# padded to 12, so archive data ends 14 bytes past the name and cpio
# pads the end to 512: anything else after the trailer is bytes the
# kernel would have to trip over.
trail_off=$(grep -a -b -o 'TRAILER!!!' "$test_root/fw.cpio" | cut -d: -f1) ||
	fail 'cannot locate TRAILER!!!'
[ "$(wc -c <"$test_root/fw.cpio")" -eq \
	$(( (trail_off + 14 + 511) / 512 * 512 )) ] ||
	fail 'archive size is not 512-padded past the TRAILER!!! entry'
[ "$(tail -c +$((trail_off + 15)) -- "$test_root/fw.cpio" | tr -d '\000' | wc -c)" \
	-eq 0 ] || fail 'bytes past the TRAILER!!! entry are not zero padding'
ok 'exactly one cpio archive, TRAILER!!! present, 512-padded tail'

# --- layout: firmware only, relative, loader-canonical ----------------
printf '%s\n' "$listing" | grep -qx 'lib' || fail 'archive has no lib root'
printf '%s\n' "$listing" | grep -qx 'lib/firmware/i915pci/adlp_dmc.bin' ||
	fail 'PCI-selected firmware missing from image'
printf '%s\n' "$listing" | grep -qx 'lib/firmware/i915base/huc.bin' ||
	fail 'baseline firmware missing from image'
if printf '%s\n' "$listing" | grep -qx 'init'; then
	fail 'archive carries /init: it must stay a firmware cpio, never an initramfs'
fi
if printf '%s\n' "$listing" | grep -q '^/'; then
	fail 'archive carries absolute paths'
fi
if printf '%s\n' "$listing" | grep -vqx 'lib\(/firmware\(/.*\)\?\)\?'; then
	fail 'archive carries paths outside lib/firmware/'
fi
ok 'firmware only: relative lib/firmware/ paths, no /init'
if cpio -itv <"$test_root/fw.cpio" 2>/dev/null | grep -qE '^[bcps]'; then
	fail 'archive carries device nodes, fifos or sockets'
fi
ok 'no device nodes, fifos or sockets'

# --- ownership, mtimes, bytes -----------------------------------------
cpio -itv <"$test_root/fw.cpio" 2>/dev/null | awk '{print $3"/"$4}' |
	sort -u | grep -qx 'root/root' ||
	fail 'archive ownership is not normalised to root:root'
ok 'ownership normalised to root:root'
mtimes=$(cpio -itv <"$test_root/fw.cpio" 2>/dev/null |
	awk '{print $6, $7, $8}' | sort -u)
[ -n "$mtimes" ] || fail 'no mtimes listed'
[ "$(printf '%s\n' "$mtimes" | wc -l)" -eq 1 ] ||
	fail "mtimes are not pinned to one epoch: $mtimes"
ok 'mtimes pinned to the reproducible epoch'

unpacked=$test_root/unpacked
mkdir -p "$unpacked"
(cd "$unpacked" && cpio -id --quiet <"$test_root/fw.cpio") ||
	fail 'archive does not extract'
cmp -s "$unpacked/lib/firmware/i915pci/adlp_dmc.bin" \
	"$sysroot/lib/firmware/i915pci/adlp_dmc.bin" ||
	fail 'blob bytes changed in the archive'
[ "$(readlink "$unpacked/lib/firmware/i915pci/tgl_guc_70.bin")" = \
	'tgl_guc_70.real.bin' ] ||
	fail 'firmware symlink not preserved relative'
ok 'blob bytes identical, firmware symlink stays relative'

# --- reproducibility ---------------------------------------------------
cp "$img" "$test_root/first.img"
run_earlyfw --all --root "$sysroot" --boot "$bootdir" \
	>"$test_root/rebuild.out" 2>&1 ||
	fail 'rebuild failed'
cmp -s "$test_root/first.img" "$img" ||
	fail 'two builds of the same input differ'
ok 'two builds of the same input are byte-identical'

# --- offline safety: no grub.cfg outside the live root -----------------
[ ! -e "$bootdir/grub.cfg" ] || fail 'offline run wrote a grub.cfg'
[ ! -e "$sysroot/boot/grub.cfg" ] || fail 'offline run touched the fixture boot grub.cfg'
[ ! -e "$bootdir/amd-ucode.img" ] || fail 'absent amd blobs still produced an image'
ok 'offline run touched only its --boot dir (no grub.cfg, no amd image)'

# --- refusals: required-but-missing firmware is fatal ------------------
printf '# bad map\n0x8086 0x03 require no-such-dir fixture-pkg\n' >"$test_root/bad.map"
if SAPHIRA_EARLYFW_MAP="$test_root/bad.map" \
	run_earlyfw --all --root "$sysroot" --boot "$test_root/boot2" \
	>"$test_root/bad.out" 2>&1; then
	fail 'missing required firmware did not fail the build'
fi
grep -q 'needs no-such-dir' "$test_root/bad.out" ||
	fail 'missing required firmware failed silently'
[ ! -e "$test_root/boot2/earlyfw-$KVER.img" ] ||
	fail 'a refused build still produced an image'
ok 'refused: required-but-missing firmware, loudly, with no output'

printf '%s\n' "earlyfw-structure: OK ($checks checks)"
