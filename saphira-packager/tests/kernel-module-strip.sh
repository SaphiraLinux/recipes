#!/bin/sh

# saphira-kernel runtime modules must carry no compiler debug payload.
#
# This is the guard for the r7 regression, at the level where it actually
# mattered. The package-size guard (kernel-release-size.sh) catches the
# magnitude; this one catches the mechanism, so a future config that produces
# debug-laden modules is rejected even if a tree happens to keep the total
# under the ceiling.
#
# 8056167 set CONFIG_DEBUG_INFO_BTF=y. olddefconfig derives
# CONFIG_DEBUG_INFO_BTF_MODULES=y from it, and derived settings live in no file
# anyone reviews, so all 218 modules shipped DWARF: 42.7 MiB -> 745.4 MiB.
# Measured on identical source: block/bfq.ko is 198,560 bytes with
# CONFIG_DEBUG_INFO_NONE=y and 2,022,008 bytes with debug info. nouveau.ko
# reached 232 MB.
#
# The config-level fix is CONFIG_DEBUG_INFO_NONE=y, and the recipe additionally
# passes INSTALL_MOD_STRIP=1. This suite proves the shipped RESULT: every
# installed .ko has zero .debug_* and zero .BTF sections.
#
# Usage: kernel-module-strip.sh APK
# Installs the given APK into a private root and scans the installed modules.
# Requires readelf on PATH and write access to a scratch directory.

set -eu

[ "$#" -eq 1 ] || {
	printf 'usage: %s KERNEL-APK\n' "$0" >&2
	exit 1
}
apk_file=$1
[ -f "$apk_file" ] || { printf 'no such file: %s\n' "$apk_file" >&2; exit 1; }

command -v readelf >/dev/null 2>&1 || { printf 'readelf required\n' >&2; exit 1; }

work=${SAPHIRA_TMPDIR:-/build/tmp}/kernel-module-strip
rm -rf "$work"
mkdir -p "$work/root/etc/apk/keys"
trap 'rm -rf "$work"' EXIT

pass=0
fail=0
ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
no() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

# --usermode is required: the build path is rootless, and apk refuses to
# create a database in a root it does not own without it.
install -m 0644 /etc/apk/keys/*.pub "$work/root/etc/apk/keys/" 2>/dev/null || true
if ! apk --root "$work/root" --initdb --usermode --keys-dir etc/apk/keys \
	--allow-untrusted add --no-scripts "$apk_file" >"$work/apk.log" 2>&1; then
	printf 'could not install %s for inspection:\n' "$apk_file" >&2
	sed 's/^/  /' "$work/apk.log" >&2
	exit 1
fi

total=$(find "$work/root/lib/modules" -name '*.ko' 2>/dev/null | wc -l)
[ "$total" -gt 0 ] || { printf 'no modules installed from %s\n' "$apk_file" >&2; exit 1; }

printf '  scanning %d installed modules\n' "$total"

bad=0
first=""
for f in $(find "$work/root/lib/modules" -name '*.ko'); do
	n=$(readelf -S -W "$f" 2>/dev/null | grep -cE '\.debug_|\.BTF' || true)
	if [ "$n" -gt 0 ]; then
		bad=$((bad + 1))
		[ -n "$first" ] || first=${f#"$work/root"}
	fi
done

if [ "$bad" -eq 0 ]; then
	ok "no .debug_* or .BTF sections in any of the $total runtime modules"
else
	no "$bad of $total runtime modules carry debug/BTF sections, e.g. $first"
fi

# A stripped module should also be well under the size that gave the r7
# failure away. nouveau.ko and i915.ko were the two worst at 232 MB and 175 MB.
worst=$(find "$work/root/lib/modules" -name '*.ko' -printf '%s %p\n' 2>/dev/null |
	sort -rn | head -1 | cut -d' ' -f1 || echo 0)
worst_mib=$((worst / 1048576))
if [ "$worst_mib" -lt 20 ]; then
	ok "largest module is ${worst_mib} MiB (r7's worst was 232 MiB)"
else
	no "largest module is ${worst_mib} MiB - runtime modules are carrying payloads again"
fi

printf 'kernel module strip: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
