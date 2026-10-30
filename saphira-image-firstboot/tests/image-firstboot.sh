#!/bin/sh
# saphira-firstboot-image suite: full wizard flow against stubs.
# Stub dialog/engine/mounts; REAL apply-network.sh validators (they
# need no root). Asserts: only install-to-disk is invoked, passwords
# never logged, boot disk refused, abort writes nothing, no marker =
# silent exit, verification catches a bad target.
set -eu

here=$(cd -- "$(dirname -- "$0")" && pwd)
tool=$here/../files/saphira-firstboot-image
testdir=${SAPHIRA_TMPDIR:-/build/tmp}/image-firstboot-test-$$
mkdir -p "$testdir/bin" "$testdir/tmp"
trap 'rm -rf "$testdir"' EXIT HUP INT TERM

failures=0
ok() { printf 'ok       %s\n' "$*"; }
bad() { printf 'FAIL     %s\n' "$*" >&2; failures=$((failures + 1)); }

sh -n "$tool" || { echo "ERROR: wizard syntax check failed" >&2; exit 1; }

# Systemd appliance: the wizard ships a unit (console fds, marker
# condition), never an openrc initd.
unit=${tool%/*}/saphira-firstboot-image.service
test -f "$unit" || { bad "wizard unit missing"; }
grep -q 'TTYPath=/dev/console' "$unit" || bad "unit console wrong"
grep -q 'ConditionPathExists=/etc/saphira-image-firstboot-required' "$unit" || bad "unit marker condition wrong"
grep -q 'WantedBy=multi-user.target' "$unit" || bad "unit install target wrong"
test ! -e "${tool%/*}/saphira-firstboot-image.initd" || bad "obsolete initd still ships"
ok "wizard unit ships for the systemd appliance"

# The boot runlevel sets no TERM and dialog is TERM-driven: without
# the default every dialog call fails instantly and the service dies
# silent (proven: env -i dialog exits 1). The wizard must default it.
grep -q 'export TERM=${TERM:-linux}' "$tool" || { bad "TERM default missing"; }

cat > "$testdir/bin/dialog" <<'EOF'
#!/bin/sh
printf 'dialog %s\n' "$*" >> "$STUB_LOG/calls"
mode=
while test $# -gt 0; do
	case $1 in
	--menu|--inputbox|--passwordbox) mode=input ;;
	--yesno|--msgbox) exit "${STUB_YESNO:-0}" ;;
	--backtitle|--title) shift 2; continue ;;
	0) ;;
	esac
	shift
done
if [ "$mode" = input ]; then
	answer=$(head -1 "$STUB_LOG/answers")
	tail -n +2 "$STUB_LOG/answers" > "$STUB_LOG/answers.new"
	mv "$STUB_LOG/answers.new" "$STUB_LOG/answers"
	printf '%s' "$answer" >&2
fi
exit 0
EOF
cat > "$testdir/bin/saphira-image" <<'EOF'
#!/bin/sh
printf 'image %s\n' "$*" >> "$STUB_LOG/calls"
if [ "$1" = list-targets ]; then
	printf 'NAME BOOT INIT PROFILE\nbios-saphira bios openrc saphira-openrc\n'
fi
exit 0
EOF
cat > "$testdir/bin/blkid" <<'EOF'
#!/bin/sh
if [ "$1" = -L ]; then printf '/dev/vdtestp2\n'; exit 0; fi
exit 1
EOF
cat > "$testdir/bin/mount" <<'EOF'
#!/bin/sh
dst=
for a in "$@"; do case $a in -*) ;; *) dst=$a ;; esac; done
mkdir -p "$dst/boot/grub" "$dst/etc"
printf 'linux /vmlinuz-7.2.3 root=PARTUUID=abc\n' > "$dst/boot/grub/grub.cfg"
printf 'vmlinuz-7.2.3\n' > "$dst/boot/grub/x"
printf '%s\n' "$STUB_HOSTNAME" > "$dst/etc/hostname"
printf 'root:$6$rounds=1$abc:1::::::\n' > "$dst/etc/shadow"
exit 0
EOF
cat > "$testdir/bin/umount" <<'EOF'
#!/bin/sh
exit 0
EOF
cat > "$testdir/bin/reboot" <<'EOF'
#!/bin/sh
printf 'reboot called\n' >> "$STUB_LOG/calls"
exit 0
EOF
cat > "$testdir/bin/poweroff" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$testdir/bin/"*

run_wizard()
{
	STUB_LOG=$testdir STUB_HOSTNAME=testhost \
	SAPHIRA_IMAGE_ALLOW_NONROOT=1 \
	SAPHIRA_IMAGE_TTY=/dev/null SAPHIRA_IMAGE_MARKER=$testdir/marker \
	SAPHIRA_IMAGE_STATE_DIR=$testdir/state SAPHIRA_TMPDIR=$testdir/tmp \
	SAPHIRA_IMAGE_DISK=/dev/vdtest SAPHIRA_IMAGE_NOEXEC=1 \
	PATH="$testdir/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
	sh "$tool" > "$testdir/out.txt" 2>&1
}

# Full flow: welcome, product, firmware, fs, hostname, skip net,
# password x2, plan yes, preview, destroy yes, reboot.
touch "$testdir/marker"
printf 'saphira\nbios\next4\ntesthost\nskip\npw1\npw1\nreboot\n' > "$testdir/answers"
: > "$testdir/calls"
run_wizard && ok "full flow exits 0" || bad "full flow exit: $(tail -2 "$testdir/out.txt")"
grep -q 'NOEXEC saphira-image install-to-disk --target bios-saphira --device /dev/vdtest --hostname testhost .* --rootfs ext4' "$testdir/out.txt" &&
	ok "engine invoked with target, device, hostname, rootfs" || bad "engine command wrong"
grep -q 'NOEXEC.*--preview' "$testdir/out.txt" && ok "preview before destroy" || bad "no preview"
grep -q 'pw1' "$testdir/calls" "$testdir/out.txt" 2>/dev/null && bad "password logged" || ok "password never logged"
grep -q 'install-to-disk' "$testdir/out.txt" && ok "engine reached" || bad "engine never called"
[ "$(grep -c 'NOEXEC saphira-image install-to-disk' "$testdir/out.txt")" = 2 ] && ok "preview and real run both issued" || bad "preview/real pair incomplete"
[ ! -e "$testdir/marker" ] && ok "marker spent on verified completion" || bad "marker kept"
grep -q 'reboot called' "$testdir/calls" && ok "reboot offered and taken" || bad "no reboot"

# Isolation: no build/export/output strings in the wizard.
if grep -nE '(^|[[:space:]])build([[:space:]]|$)|export --| --output([[:space:]]|$)' "$tool"; then
	bad "wizard can build image files"
else
	ok "install-to-disk only"
fi

# Abort at first confirmation writes nothing and keeps the marker.
touch "$testdir/marker2"
printf 'saphira\nbios\next4\ntesthost2\nskip\npw1\npw1\n' > "$testdir/answers"
: > "$testdir/calls"
STUB_YESNO=1 STUB_LOG=$testdir STUB_HOSTNAME=x \
SAPHIRA_IMAGE_ALLOW_NONROOT=1 \
SAPHIRA_IMAGE_TTY=/dev/null SAPHIRA_IMAGE_MARKER=$testdir/marker2 \
SAPHIRA_IMAGE_STATE_DIR=$testdir/state SAPHIRA_TMPDIR=$testdir/tmp \
SAPHIRA_IMAGE_DISK=/dev/vdtest SAPHIRA_IMAGE_NOEXEC=1 \
PATH="$testdir/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
sh "$tool" >/dev/null 2>&1 && bad "abort accepted" || ok "abort refused"
[ -e "$testdir/marker2" ] && ok "marker kept on abort" || bad "marker spent on abort"

# No marker: silent success, engine untouched.
: > "$testdir/calls"
STUB_LOG=$testdir SAPHIRA_IMAGE_ALLOW_NONROOT=1 SAPHIRA_IMAGE_TTY=/dev/null SAPHIRA_IMAGE_MARKER=$testdir/none \
SAPHIRA_IMAGE_STATE_DIR=$testdir/state SAPHIRA_TMPDIR=$testdir/tmp \
PATH="$testdir/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
sh "$tool" >/dev/null 2>&1 && ok "no-marker silent exit" || bad "no-marker exit"
grep -q 'install-to-disk' "$testdir/calls" 2>/dev/null && bad "no-marker ran engine" || ok "no-marker clean"

if test "$failures" -ne 0; then printf '%d FAILURES\n' "$failures" >&2; exit 1; fi
printf 'all image-firstboot cases pass\n'
