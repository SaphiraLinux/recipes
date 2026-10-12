#!/bin/sh

# saphira-kernel public-distribution size and payload guards.
#
# Saphira is a public distribution. Between r5 and r7 the kernel package grew
# from 32 MiB to 600 MiB compressed and from ~70 MiB to ~2.4 GiB installed, and
# it shipped for three revisions before anyone looked. Two independent causes:
#
#   d2e581d  installed the prepared external-module build tree at
#            /usr/src/linux-<ver>-saphira into a RUNTIME package:
#            +1648 MiB, +77,655 files.
#   8056167  enabled CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT and
#            CONFIG_DEBUG_INFO_BTF. olddefconfig DERIVES
#            CONFIG_DEBUG_INFO_BTF_MODULES=y from the latter, and a derived
#            setting appears in no file a reviewer reads. All 218 modules then
#            shipped a DWARF database: /lib/modules 42.7 MiB -> 745.4 MiB, with
#            nouveau.ko at 232 MB and i915.ko at 175 MB.
#
# Neither was visible in a build log, a module count, or /boot. The only place
# the regression was ever visible is a size comparison, which is why this suite
# exists and why it is a release gate rather than a note.
#
# The baseline below is r5, the last known-good packaging.

set -eu

[ "$#" -eq 1 ] || {
	printf 'usage: %s KERNEL-APK\n' "$0" >&2
	printf '  pass the published saphira-kernel APK to check\n' >&2
	exit 1
}
apk_file=$1

# r5, the known-good public packaging baseline: 73,289,642 bytes installed.
# The ceiling is 2x, as a deliberate reviewed value. Raising it is a policy
# decision, not a build outcome, and must be done here in the open.
BASELINE_INSTALLED=73289642
CEILING_INSTALLED=$((BASELINE_INSTALLED * 2))

pass=0
fail=0
ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
no() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

[ -f "$apk_file" ] || { printf 'no such file: %s\n' "$apk_file" >&2; exit 1; }

# adbdump gives the payload tree with per-file sizes, so this reads the package
# as it will actually be installed rather than as it was staged.
dump=$(apk adbdump "$apk_file" 2>/dev/null) || {
	printf 'apk adbdump failed on %s\n' "$apk_file" >&2
	exit 1
}

printf '  package: %s (%s bytes)\n' "$(basename "$apk_file")" "$(stat -c %s "$apk_file")"

# ------------------------------------------------ 1. no /usr/src in the payload
# Counted by walking the adbdump tree properly. A grep for "usr" would also
# match any path merely containing it, and an awk that assumed a flat shape
# silently reported 0 for r7, which ships 77,655 /usr/src files.
src_entries=$(printf '%s\n' "$dump" | python3 -c '
import sys
stack={}
n=0
for ln in sys.stdin:
    if not ln.startswith(" "): continue
    b=ln.strip(); i=len(ln)-len(b)
    if b.startswith("- name: "):
        nm=b[8:]
        for k in [k for k in stack if k>=i]: del stack[k]
        stack[i]=nm
    elif b.startswith("size: "):
        p="/".join(stack[k] for k in sorted(stack) if stack[k])
        if p.startswith("usr/src/"): n+=1
print(n)')
if [ "$src_entries" -eq 0 ]; then
	ok "payload contains no /usr/src entries"
else
	no "payload contains $src_entries /usr/src entries - a runtime kernel must not ship build source"
fi

# ------------------------------------- 2. no module-tree pointers in the payload
if printf '%s\n' "$dump" | grep -qE '^ +- name: (build|source)$'; then
	no "payload contains a modules build/source entry - must not ship a dangling build pointer"
else
	ok "payload contains no modules build/source pointer"
fi

# ------------------------------------------- 3. installed-size within the ceiling
installed=$(printf '%s\n' "$dump" | awk '/installed-size:/ {print $2; exit}')
[ -n "$installed" ] || { printf 'could not read installed-size\n' >&2; exit 1; }
if [ "$installed" -le "$CEILING_INSTALLED" ]; then
	ok "installed-size $installed within ceiling $CEILING_INSTALLED (2x r5 = $BASELINE_INSTALLED)"
else
	no "installed-size $installed EXCEEDS ceiling $CEILING_INSTALLED (r5 baseline $BASELINE_INSTALLED)"
fi
# Report the ratio so a reviewer sees the margin, not just the verdict.
printf '       installed-size is %d%% of the r5 baseline\n' \
	"$((installed * 100 / BASELINE_INSTALLED))"

# ---------------------------------------- 4. /lib/modules is runtime-sized
# r5 shipped 43.7 MiB of modules for 218 .ko files. Hundreds of MiB means a
# debug database leaked in, which is the r7 failure mode.
mods_bytes=$(printf '%s\n' "$dump" | python3 -c '
import sys
stack={}
total=0
for ln in sys.stdin:
    if not ln.startswith(" "): continue
    b=ln.strip(); i=len(ln)-len(b)
    if b.startswith("- name: "):
        nm=b[8:]
        for k in [k for k in stack if k>=i]: del stack[k]
        stack[i]=nm
    elif b.startswith("size: "):
        p="/".join(stack[k] for k in sorted(stack) if stack[k])
        if p.startswith("lib/modules/"): total+=int(b.split()[1])
print(total)')
mods_mib=$((mods_bytes / 1048576))
if [ "$mods_mib" -lt 150 ]; then
	ok "/lib/modules is ${mods_mib} MiB (tens of MiB, runtime-sized)"
else
	no "/lib/modules is ${mods_mib} MiB - a debug database has leaked into the modules"
fi

# ------------------------------------------------- 5. module count sanity
# 218 in r5. r10 ships 216 because CONFIG_RD_ZSTD (initramfs support) selects
# the zstd decompressor built-in, so lib/zstd/zstd_{common,decompress}.ko are
# no longer separate modules; the same code is inside vmlinuz. The floor exists
# to catch a config edit that quietly drops a hardware driver family.
ko_count=$(printf '%s\n' "$dump" | python3 -c '
import sys
stack={}; n=0
for ln in sys.stdin:
    if not ln.startswith(" "): continue
    b=ln.strip(); i=len(ln)-len(b)
    if b.startswith("- name: "):
        nm=b[8:]
        for k in [k for k in stack if k>=i]: del stack[k]
        stack[i]=nm
    elif b.startswith("size: "):
        p="/".join(stack[k] for k in sorted(stack) if stack[k])
        if p.endswith(".ko"): n+=1
print(n)')
if [ "$ko_count" -ge 200 ]; then
	ok "module count $ko_count (>=200, hardware/router support intact)"
else
	no "module count $ko_count is below the 200 floor - hardware support may have been dropped"
fi

printf 'kernel release guard: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
