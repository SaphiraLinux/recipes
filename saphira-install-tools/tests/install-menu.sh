#!/bin/sh
# saphira-install-menu suite: full menu flow against a stub dialog,
# stub planner/engine, scratch manifest. No disks, no network, no
# engine: SAPHIRA_MENU_* test overrides contain everything.
set -eu

here=$(cd -- "$(dirname -- "$0")" && pwd)
tool=$here/../files/saphira-install-menu
testdir=${SAPHIRA_TMPDIR:-/build/tmp}/install-menu-test-$$
mkdir -p "$testdir/bin" "$testdir/profiles"
trap 'rm -rf "$testdir"' EXIT HUP INT TERM

failures=0
ok() { printf 'ok       %s\n' "$*"; }
bad() { printf 'FAIL     %s\n' "$*" >&2; failures=$((failures + 1)); }

sh -n "$tool" || { echo "ERROR: menu syntax check failed" >&2; exit 1; }

printf 'saphirad-systemd\nsaphira-openrc\n' > "$testdir/profiles-list"
printf 'saphirad-systemd\n' > "$testdir/profiles/saphirad-systemd"
printf 'saphira-openrc\n' > "$testdir/profiles/saphira-openrc"

# Stub dialog: answers consumed in order for --menu/--inputbox,
# yes for --yesno/--msgbox. Every invocation is logged.
cat > "$testdir/bin/dialog" <<'EOF'
#!/bin/sh
printf 'dialog %s\n' "$*" >> "$STUB_LOG/calls"
mode=
init=
while test $# -gt 0; do
	case $1 in
	--menu) mode=menu ;;
	--inputbox) mode=input ;;
	--yesno|--msgbox) exit "${STUB_YESNO:-0}" ;;
	--backtitle|--title) shift 2; continue ;;
	0) ;;
	*) last=$1 ;;
	esac
	shift
done
case $mode in
menu|input)
	answer=$(head -1 "$STUB_LOG/answers")
	tail -n +2 "$STUB_LOG/answers" > "$STUB_LOG/answers.new"
	mv "$STUB_LOG/answers.new" "$STUB_LOG/answers"
	# Real dialog draws on stdout and answers on stderr (the
	# 2>&1 >tty idiom); the stub obeys the same contract.
	printf '%s' "$answer" >&2
	;;
esac
exit 0
EOF
chmod +x "$testdir/bin/dialog"

# Stub planner/engine on PATH.
cat > "$testdir/bin/saphira-install-plan" <<'EOF'
#!/bin/sh
printf 'plan %s\n' "$*" >> "$STUB_LOG/calls"
exit 0
EOF
cat > "$testdir/bin/saphira-image" <<'EOF'
#!/bin/sh
printf 'image %s\n' "$*" >> "$STUB_LOG/calls"
exit 0
EOF
chmod +x "$testdir/bin/saphira-install-plan" "$testdir/bin/saphira-image"

# Answers: firmware auto, systemd, ext4, direct, base, hostname,
# (network skipped), then two confirmations.
printf 'auto\nsystemd\next4\ndirect\nbase\ntesthost\n' > "$testdir/answers"
: > "$testdir/calls"

STUB_LOG=$testdir \
DIALOG_BIN="$testdir/bin/dialog" \
PATH="$testdir/bin:/usr/bin:/bin" \
INSTALL_TTY=/dev/null \
SAPHIRA_PROFILE_ROOT="$testdir/profiles" \
SAPHIRA_MENU_SKIP_NET=1 SAPHIRA_MENU_DISK=/dev/testdisk \
SAPHIRA_MENU_MANIFEST="$testdir/install.conf" SAPHIRA_MENU_NOEXEC=1 \
sh "$tool" > "$testdir/out.txt" 2>&1 || {
	bad menu-flow-exit
	sed -n '1,5p' "$testdir/out.txt" >&2
}

grep -q 'NOEXEC saphira-image install-to-disk --target bios-saphirad --device /dev/testdisk --hostname testhost' "$testdir/out.txt" 2>/dev/null &&
	ok menu-drives-engine || bad menu-engine-command
grep -q '^FIRMWARE=bios$' "$testdir/install.conf" 2>/dev/null && ok firmware-autodetect || bad firmware-not-detected
grep -q '^PROFILE=saphirad-systemd$' "$testdir/install.conf" 2>/dev/null && ok profile-derived || bad profile-not-derived
grep -q '^ROLE=base$' "$testdir/install.conf" 2>/dev/null && ok role-recorded || bad role-not-recorded
grep -c '^dialog ' "$testdir/calls" | grep -q . && ok dialog-drove-flow || bad dialog-unused

# Abort path: a "no" at first confirmation writes nothing destructive.
printf 'auto\nopenrc\next4\ndirect\nbase\ntesthost2\n' > "$testdir/answers"
: > "$testdir/calls"
STUB_YESNO=1 STUB_LOG=$testdir \
DIALOG_BIN="$testdir/bin/dialog" \
PATH="$testdir/bin:/usr/bin:/bin" \
INSTALL_TTY=/dev/null \
SAPHIRA_PROFILE_ROOT="$testdir/profiles" \
SAPHIRA_MENU_SKIP_NET=1 SAPHIRA_MENU_DISK=/dev/testdisk2 \
SAPHIRA_MENU_MANIFEST="$testdir/install2.conf" SAPHIRA_MENU_NOEXEC=1 \
sh "$tool" >/dev/null 2>&1 && bad abort-accepted || ok abort-refused
grep -q 'install-to-disk --target' "$testdir/calls" 2>/dev/null && bad abort-ran-engine || ok abort-clean

if test "$failures" -ne 0; then printf '%d FAILURES\n' "$failures" >&2; exit 1; fi
printf 'all install-menu cases pass\n'
