#!/bin/sh
# saphira-utmp-boot regression tests (hermetic, no reboot required).
#
# The writer keys everything on the kernel's own btime, so a scratch
# root exercises the exact production logic: fresh boot, re-run,
# reboot-after-crash, and corrupt input. Records are verified
# byte- and struct-level (utmpdump plus field asserts): musl's
# getutxent is a stub that always returns NULL, so coreutils
# who/uptime can never display records from ANY file on Saphira -
# asking them to read the scratch file proves nothing. What they DO
# read in production is the fallback chain (now - /proc/uptime once
# no stale seed shadows it), covered by the image-exclude guards
# plus a best-effort namespace check below.
#
# What this does NOT prove (stated openly): an actual reboot, where
# OpenRC runs the initd in the boot runlevel and systemd the unit
# before user sessions. That needs a booted image and is an operator
# acceptance step, not something a hermetic suite can fake.

set -eu

test_tmp_base=${SAPHIRA_TMPDIR:-/build/test-tmp}
mkdir -p "$test_tmp_base"
work=$(mktemp -d "$test_tmp_base/saphira-utmp-test.XXXXXX")
trap 'rm -rf -- "$work"' EXIT HUP INT TERM

fail() { printf '%s\n' "saphira-utmp: FAIL: $*" >&2; exit 1; }
ok() { printf '%s\n' "  ok   $*"; }

tool_src=$(CDPATH= cd -- "$(dirname -- "$0")/../files" && pwd)
cc=${CC:-gcc}
command -v "$cc" >/dev/null 2>&1 || fail "no C compiler ($cc)"
command -v utmpdump >/dev/null 2>&1 || fail "no utmpdump (util-linux)"
command -v who >/dev/null 2>&1 || fail "no who (coreutils)"
command -v uptime >/dev/null 2>&1 || fail "no uptime (coreutils)"

"$cc" -std=c11 -O2 -Wall -Wextra -Werror \
	-o "$work/saphira-utmp-boot" \
	"$tool_src/saphira-utmp-boot.c" || fail "test compile failed"
tool=$work/saphira-utmp-boot
ok "test binary compiles warning-free with -Werror"

btime=$(awk '/^btime /{print $2}' /proc/stat) || fail "no btime"
[ -n "$btime" ] || fail "empty btime"
ok "kernel btime reads as $btime"

# --- 1. fresh boot: empty root gains both records --------------------
root=$work/root1
mkdir -p "$root/var/run" "$root/var/log"
SAPHIRA_UTMP_ROOT="$root" "$tool" || fail "fresh-root run failed"
[ -f "$root/var/run/utmp" ] || fail "no utmp created"
[ -f "$root/var/log/wtmp" ] || fail "no wtmp created"
[ "$(stat -c %a "$root/var/run/utmp")" = 644 ] ||
	fail "utmp is not 0644"
[ "$(stat -c %a "$root/var/log/wtmp")" = 644 ] ||
	fail "wtmp is not 0644"
# struct-level asserts: the record is type BOOT_TIME for this boot
python3 - "$root/var/run/utmp" "$btime" <<'PY' || fail "utmp record fields wrong"
import struct, sys
path, boot = sys.argv[1], int(sys.argv[2])
rec = open(path, 'rb').read()
assert len(rec) == 400, len(rec)
(typ, pid, line, rid, user, host, e1, e2, sess, tv_s, tv_u) = struct.unpack('<hxxi32s4s32s256shhqqq40s', rec)[:11]
assert typ == 2, typ
assert tv_s == boot, (tv_s, boot)
assert tv_u == 0
assert user.rstrip(b'\0') == b'reboot', user
assert line.rstrip(b'\0') == b'~', line
PY
ok "fresh boot writes BOOT_TIME keyed on btime ($btime)"

# utmpdump (direct file reader, unlike musl getutxent) shows it too
utmpdump "$root/var/run/utmp" | grep -q 'reboot' ||
	fail "utmpdump does not show the reboot record"

# --- 2. re-run is a no-op (restart-safe) ------------------------------
before_utmp=$(sha256sum "$root/var/run/utmp" | cut -d' ' -f1)
before_wtmp=$(sha256sum "$root/var/log/wtmp" | cut -d' ' -f1)
SAPHIRA_UTMP_ROOT="$root" "$tool" || fail "second run failed"
[ "$(sha256sum "$root/var/run/utmp" | cut -d' ' -f1)" = "$before_utmp" ] ||
	fail "re-run rewrote utmp"
[ "$(sha256sum "$root/var/log/wtmp" | cut -d' ' -f1)" = "$before_wtmp" ] ||
	fail "re-run rewrote wtmp"
ok "re-run is byte-identical (no duplicate records)"

# --- 3. stale record: previous boot's entry is kept, current appended
root3=$work/root3
mkdir -p "$root3/var/run" "$root3/var/log"
stale=$((btime - 86400))
python3 - "$root3/var/run/utmp" "$stale" <<'PY'
import struct, sys
path, ts = sys.argv[1], int(sys.argv[2])
# struct utmpx, x86_64 musl layout: verified against
# offsetof output (tv at 344, sizeof 400). Tail content is
# zeroes; only type/pid/line/id/user/tv matter here.
rec = struct.pack('<hxxi32s4s32s256shhqqq40s',
                  2, 1, b'~', b'~~', b'reboot', b'',
                  0, 0, 0, ts, 0, b'')
assert len(rec) == 400, len(rec)
open(path, 'wb').write(rec)
PY
SAPHIRA_UTMP_ROOT="$root3" "$tool" || fail "stale-record run failed"
count=$(utmpdump "$root3/var/run/utmp" | grep -c 'reboot') || true
[ "$count" = 2 ] || fail "expected old+new BOOT_TIME records, got $count"
# the newest record must carry the current btime
python3 - "$root3/var/run/utmp" "$btime" <<'PY' || fail "newest record is not the current boot"
import struct, sys
path, boot = sys.argv[1], int(sys.argv[2])
data = open(path, 'rb').read()
assert len(data) == 800, len(data)
rec = data[400:]
(typ, pid, line, rid, user, host, e1, e2, sess, tv_s, tv_u) = struct.unpack('<hxxi32s4s32s256shhqqq40s', rec)[:11]
assert typ == 2, typ
assert tv_s == boot, (tv_s, boot)
PY
SAPHIRA_UTMP_ROOT="$root3" "$tool" || fail "post-stale re-run failed"
count2=$(utmpdump "$root3/var/run/utmp" | grep -c 'reboot') || true
[ "$count2" = 2 ] || fail "post-stale re-run must not append again"
ok "stale previous-boot record is kept, current boot appended once"

# --- 4. corrupt utmp fails loud, writes nothing -----------------------
root4=$work/root4
mkdir -p "$root4/var/run" "$root4/var/log"
printf 'garbage' > "$root4/var/run/utmp"
before=$(sha256sum "$root4/var/run/utmp" | cut -d' ' -f1)
if SAPHIRA_UTMP_ROOT="$root4" "$tool" 2>/dev/null; then
	fail "corrupt utmp did not fail"
fi
[ "$(sha256sum "$root4/var/run/utmp" | cut -d' ' -f1)" = "$before" ] ||
	fail "corrupt utmp was mutated"
ok "corrupt utmp fails loud without writing"

# --- 5. recipe never auto-enables --------------------------------------
pkgdir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if grep -qE 'rc-update|systemctl enable' "$pkgdir/recipe.sh"; then
	fail "recipe enables the service (images enable, never packages)"
fi
[ -f "$pkgdir/files/saphira-utmp-boot.initd" ] ||
	fail "missing OpenRC unit"
[ -f "$pkgdir/files/saphira-utmp-boot.service" ] ||
	fail "missing systemd unit"
ok "dual-init units ship, nothing auto-enables"

# --- 6. coreutils fallback chain (best effort) -----------------------
# With records present but the stale seed hidden (fresh-image
# condition), uptime/who -b must report the kernel boot, proving
# the operator requirement end to end. Needs user namespaces;
# skipped loudly where unavailable (the static guards in
# clean-image-guards.sh cover the image side unconditionally).
if command -v unshare >/dev/null 2>&1 &&
	unshare --map-root-user true 2>/dev/null; then
	mkdir -p "$work/emptyseed"
	# Make the scratch utmp look like a fresh boot product: on a
	# real image the writer creates it during the boot runlevel, so
	# its mtime is the boot time. The fallback chain reads exactly
	# this mtime (musl cannot parse records), so stamping btime
	# reproduces production precisely.
	touch -d "@$btime" "$root/var/run/utmp" ||
		fail "cannot stamp scratch utmp"
	got=$(unshare --map-root-user -m sh -c "
		mount --bind $work/emptyseed /var/lib/systemd &&
		mount --bind $root/var/run/utmp /var/run/utmp &&
		uptime" 2>/dev/null) || fail "namespaced uptime failed"
	echo "$got" | grep -q 'up ' || fail "no uptime in: $got"
	# the reported uptime must be the kernel's, not image age:
	# compare against /proc/uptime with a generous bound
	up_ns=$(printf '%s\n' "$got" | python3 -c "
import re, sys
m = re.search(r'up\s+(?:(\d+)\s+days?,?\s+)?(\d+):(\d+)', sys.stdin.read())
if not m: sys.exit('no uptime field')
d, h, mi = int(m.group(1) or 0), int(m.group(2)), int(m.group(3))
print(d * 86400 + h * 3600 + mi * 60)
") || fail "could not parse namespaced uptime: $got"
	up_now=$(awk '{print $1}' /proc/uptime)
	python3 - "$up_now" "$up_ns" <<'PY' || fail "fallback uptime disagrees with /proc/uptime"
import sys
now, got = float(sys.argv[1]), float(sys.argv[2])
assert abs(now - got) < 300, (now, got)
PY
	who_out=$(unshare --map-root-user -m sh -c "
		mount --bind $work/emptyseed /var/lib/systemd &&
		who -b" 2>/dev/null) || fail "namespaced who -b failed"
	echo "$who_out" | grep -q 'system boot' ||
		fail "who -b reports no system boot: $who_out"
	ok "fallback chain reports the kernel boot (no stale seed)"
else
	printf '%s\n' "  skip  user namespaces unavailable; fallback covered by image guards"
fi

printf '%s\n' "saphira-utmp: all checks passed"
