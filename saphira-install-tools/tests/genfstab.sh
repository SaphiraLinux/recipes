#!/bin/sh
# saphira-genfstab suite: fstype-aware pass/options against stub
# findmnt/blkid. A vfat ESP must never fail a boot (nofail, pass 0);
# / keeps pass 1 and its hard requirement.
set -eu

here=$(cd -- "$(dirname -- "$0")" && pwd)
tool=$here/../files/saphira-genfstab
testdir=${SAPHIRA_TMPDIR:-/build/tmp}/genfstab-test-$$
mkdir -p "$testdir/bin" "$testdir/mnt/boot/efi"
trap 'rm -rf "$testdir"' EXIT HUP INT TERM

failures=0
ok() { printf 'ok       %s\n' "$*"; }
bad() { printf 'FAIL     %s\n' "$*" >&2; failures=$((failures + 1)); }

sh -n "$tool" || { echo "ERROR: syntax check failed" >&2; exit 1; }

cat > "$testdir/bin/findmnt" <<'EOF'
#!/bin/sh
# Stub: -Rrn lists the target subtree; otherwise -o FIELD ... TARGET.
if [ "$1" = -Rrn ]; then
	printf '%s\n%s\n' "$STUB_MNT" "$STUB_MNT/boot/efi"
	exit 0
fi
while test $# -gt 0; do
	case $1 in
	-o) field=$2; shift 2 ;;
	--target) tgt=$2; shift 2 ;;
	*) shift ;;
	esac
done
case $field in
SOURCE) case $tgt in
	*"/boot/efi") printf '/dev/FAKEP1\n' ;;
	*) printf '/dev/FAKEP3\n' ;; esac ;;
FSTYPE) case $tgt in
	*"/boot/efi") printf 'vfat\n' ;;
	*) printf 'ext4\n' ;; esac ;;
OPTIONS) printf 'rw,relatime\n' ;;
TARGET) printf '%s\n' "$tgt" ;;
esac
exit 0
EOF
cat > "$testdir/bin/blkid" <<'EOF'
#!/bin/sh
printf 'FAKE-UUID\n'
exit 0
EOF
chmod +x "$testdir/bin/findmnt" "$testdir/bin/blkid"

STUB_MNT=$testdir/mnt SAPHIRA_FINDMNT=$testdir/bin/findmnt SAPHIRA_BLKID=$testdir/bin/blkid \
PATH="$testdir/bin:/usr/bin:/bin" \
sh "$tool" "$testdir/mnt" > "$testdir/fstab" 2>&1 || bad "genfstab exit: $(cat "$testdir/fstab")"
grep -q 'FAKE-UUID	/	ext4	rw,relatime	0	1' "$testdir/fstab" &&
	ok "root keeps pass 1" || bad "root line wrong: $(cat "$testdir/fstab")"
grep -q 'FAKE-UUID	/boot/efi	vfat	rw,relatime,nofail,x-systemd.device-timeout=5s	0	0' "$testdir/fstab" &&
	ok "ESP nofail pass 0" || bad "ESP line wrong: $(cat "$testdir/fstab")"

if test "$failures" -ne 0; then printf '%d FAILURES\n' "$failures" >&2; exit 1; fi
printf 'all genfstab cases pass\n'
