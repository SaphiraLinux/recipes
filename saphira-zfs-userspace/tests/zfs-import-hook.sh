#!/bin/sh
# zfs-import-hook suite: the 20-zfs-import root.d hook against stub
# binaries and fixture cmdlines. No pool, no devices, no root.
set -eu

here=$(cd -- "$(dirname -- "$0")" && pwd)
hook=$here/../files/20-zfs-import
testdir=${SAPHIRA_TMPDIR:-/build/tmp}/zfs-hook-test-$$
mkdir -p "$testdir/bin" "$testdir/newroot"
trap 'rm -rf "$testdir"' EXIT HUP INT TERM

failures=0
ok() { printf 'ok       %s\n' "$*"; }
bad() { printf 'FAIL     %s\n' "$*" >&2; failures=$((failures + 1)); }

sh -n "$hook" || { echo "ERROR: hook syntax check failed" >&2; exit 1; }

# Stub zpool/mount: log argv, succeed or fail per stub control files.
cat > "$testdir/bin/zpool" <<'EOF'
#!/bin/sh
printf 'zpool %s\n' "$*" >> "$STUB_LOG/calls"
test -f "$STUB_LOG/zpool-fail" && exit 1
exit 0
EOF
cat > "$testdir/bin/mount" <<'EOF'
#!/bin/sh
printf 'mount %s\n' "$*" >> "$STUB_LOG/calls"
test -f "$STUB_LOG/mount-fail" && exit 1
exit 0
EOF
chmod +x "$testdir/bin/zpool" "$testdir/bin/mount"

run_hook()
{
	STUB_LOG=$testdir PATH="$testdir/bin:/usr/bin:/bin" \
		PROC_CMDLINE=$testdir/cmdline NEWROOT=$testdir/newroot \
		sh "$hook" 2>"$testdir/stderr"
}

# ZFS root: import by partuuid, then mount the dataset.
printf 'BOOT_IMAGE=/boot/vmlinuz root=ZFS=tank/ROOTS/saphira rw\n' > "$testdir/cmdline"
: > "$testdir/calls"
run_hook && ok zfs-root-exits-0 || bad zfs-root-exit
grep -q 'zpool import -N -d /dev/disk/by-partuuid tank' "$testdir/calls" && ok import-partuuid-first || bad import-not-partuuid
grep -q 'mount -t zfs tank/ROOTS/saphira' "$testdir/calls" && ok mount-dataset || bad mount-no-dataset

# Plain root: no-op, nothing called.
printf 'BOOT_IMAGE=/boot/vmlinuz root=PARTUUID=deadbeef rw\n' > "$testdir/cmdline"
: > "$testdir/calls"
run_hook && ok plain-root-noop || bad plain-root-exit
test ! -s "$testdir/calls" && ok plain-root-no-calls || bad plain-root-called

# Malformed ZFS root (pool without dataset): loud failure.
printf 'root=ZFS=tank\n' > "$testdir/cmdline"
run_hook 2>/dev/null && bad malformed-accepted || ok malformed-refused

# Failing import: loud failure, no mount attempted.
printf 'root=ZFS=tank/ROOTS/saphira\n' > "$testdir/cmdline"
: > "$testdir/calls" && : > "$testdir/zpool-fail"
run_hook 2>/dev/null && bad import-fail-accepted || ok import-fail-refused
grep -q '^mount ' "$testdir/calls" && bad mount-after-failed-import || ok no-mount-after-failed-import
rm -f "$testdir/zpool-fail"

if test "$failures" -ne 0; then printf '%d FAILURES\n' "$failures" >&2; exit 1; fi
printf 'all zfs-import-hook cases pass\n'
