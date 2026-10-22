#!/bin/sh
# lvm-activate-hook suite: the 20-lvm-activate root.d hook against
# stub binaries and fixture cmdlines. No groups, no devices, no root.
set -eu

here=$(cd -- "$(dirname -- "$0")" && pwd)
hook=$here/../files/20-lvm-activate
testdir=${SAPHIRA_TMPDIR:-/build/tmp}/lvm-hook-test-$$
mkdir -p "$testdir/bin" "$testdir/newroot"
trap 'rm -rf "$testdir"' EXIT HUP INT TERM

failures=0
ok() { printf 'ok       %s\n' "$*"; }
bad() { printf 'FAIL     %s\n' "$*" >&2; failures=$((failures + 1)); }

sh -n "$hook" || { echo "ERROR: hook syntax check failed" >&2; exit 1; }

cat > "$testdir/bin/vgchange" <<'EOF'
#!/bin/sh
printf 'vgchange %s\n' "$*" >> "$STUB_LOG/calls"
test -f "$STUB_LOG/vgchange-fail" && exit 1
exit 0
EOF
cat > "$testdir/bin/mount" <<'EOF'
#!/bin/sh
printf 'mount %s\n' "$*" >> "$STUB_LOG/calls"
test -f "$STUB_LOG/mount-fail" && exit 1
exit 0
EOF
chmod +x "$testdir/bin/vgchange" "$testdir/bin/mount"

run_hook()
{
	STUB_LOG=$testdir PATH="$testdir/bin:/usr/bin:/bin" \
		PROC_CMDLINE=$testdir/cmdline NEWROOT=$testdir/newroot \
		sh "$hook" 2>"$testdir/stderr"
}

# device-mapper root: activate, then mount here.
printf 'root=/dev/mapper/saphira-root rw\n' > "$testdir/cmdline"
: > "$testdir/calls"
run_hook && ok dm-root-exits-0 || bad dm-root-exit
grep -q 'vgchange -ay' "$testdir/calls" && ok activates || bad no-activation
grep -q 'mount /dev/mapper/saphira-root' "$testdir/calls" && ok mounts-dm || bad no-dm-mount

# plain root: activation still runs (covers UUID-on-LV, which /init
# mounts itself), but this hook mounts nothing.
printf 'root=PARTUUID=deadbeef rw\n' > "$testdir/cmdline"
: > "$testdir/calls"
run_hook && ok plain-root-exits-0 || bad plain-root-exit
grep -q 'vgchange -ay' "$testdir/calls" && ok plain-still-activates || bad plain-no-activation
grep -q '^mount ' "$testdir/calls" && bad plain-mounted || ok plain-not-mounted

# failing activation: loud failure before any mount.
printf 'root=/dev/mapper/saphira-root rw\n' > "$testdir/cmdline"
: > "$testdir/calls" && : > "$testdir/vgchange-fail"
run_hook 2>/dev/null && bad activation-fail-accepted || ok activation-fail-refused
grep -q '^mount ' "$testdir/calls" && bad mount-after-failed-activation || ok no-mount-after-failed-activation
rm -f "$testdir/vgchange-fail"

if test "$failures" -ne 0; then printf '%d FAILURES\n' "$failures" >&2; exit 1; fi
printf 'all lvm-activate-hook cases pass\n'
