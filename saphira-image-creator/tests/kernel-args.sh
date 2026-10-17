#!/bin/bash
# --kernel-arg must land in the image's GRUB_CMDLINE_LINUX, and only
# when asked for.
#
# Found by needing to boot a generated image headlessly: the shipped
# default carries `console=tty0` only, and Saphira deliberately ships no
# serial getty in the runlevel, so there is no way to reach a running
# system over serial. That is the right default for real hardware and the
# wrong one for a VM or an installer medium, so the argument is opt-in
# per build rather than assumed product-wide.
#
# This exercises the transform that rewrites GRUB_CMDLINE_LINUX, which is
# the only place the image's kernel command line is decided.

set -uo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
image=${SAPHIRA_IMAGE:-$here/../files/saphira-image}

failures=0
ok() { printf 'ok       %s\n' "$*"; }
bad() { printf 'FAIL     %s\n' "$*" >&2; failures=$((failures + 1)); }

test -r "$image" || { printf 'not readable: %s\n' "$image" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# The rewrite is a python3 heredoc inside the tool. Run exactly that code
# against a fixture, so this cannot drift from what builds the image.
rewrite()
{
	local defgrub=$1 partuuid=$2 getty_opt=$3 kernel_args=$4
	BOOT=${BOOT:-bios}
	INIT=${INIT:-openrc}
	mnt=$(dirname "$(dirname "$defgrub")")
	KERNEL_ARGS=$kernel_args
	# Extract the embedded transform and run it.
	sed -n "/^import re$/,/^PY$/p" "$image" |
		sed '$d' > "$work/transform.py"
	python3 "$work/transform.py" "$defgrub" "$partuuid" "$getty_opt" "$kernel_args"
}

fixture()
{
	local name=$1 cmdline=$2
	printf 'GRUB_DEFAULT=0\nGRUB_TIMEOUT=0\nGRUB_CMDLINE_LINUX="%s"\n' "$cmdline" \
		> "$work/$name"
	printf '%s\n' "$work/$name"
}

value_of()
{
	sed -n 's/^GRUB_CMDLINE_LINUX="\(.*\)"$/\1/p' "$1"
}

printf '%s\n' '# no --kernel-arg: the image keeps the packaged default'

f=$(fixture plain 'rootfstype=ext4 rw rootwait console=tty0 raid=noautodetect root=/dev/loop0p2')
rewrite "$f" 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' '' '' 2>/dev/null
value=$(value_of "$f")
case $value in
*'root=PARTUUID=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'*)
	ok 'the deployment-stable root= is still substituted' ;;
*)
	bad "root= was not substituted: $value" ;;
esac
case $value in
*'/dev/loop0p2'*) bad 'the build-host loop device leaked into the image' ;;
*) ok 'no build-host loop device leaks into the image' ;;
esac
case $value in
*'console=ttyS0'*) bad 'a serial console appeared without being asked for' ;;
*) ok 'no serial console is added unless requested' ;;
esac

printf '%s\n' '# --kernel-arg appends what was asked for'

f=$(fixture serial 'rootfstype=ext4 rw rootwait console=tty0 root=/dev/loop0p2')
rewrite "$f" 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' '' 'console=ttyS0,115200' 2>/dev/null
value=$(value_of "$f")
case $value in
*'console=ttyS0,115200'*) ok 'a requested serial console is present' ;;
*) bad "the requested argument is missing: $value" ;;
esac
case $value in
# Last wins: for console= the final value is /dev/console, so a request
# that must take effect has to come after the packaged default.
*'console=tty0'*'console=ttyS0,115200'*)
	ok 'the requested argument follows the default tokens, so it wins' ;;
*)
	bad "argument ordering is wrong, the request must come last: $value" ;;
esac

printf '%s\n' '# several arguments accumulate'

f=$(fixture multi 'console=tty0 root=/dev/loop0p2')
rewrite "$f" 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' '' 'console=ttyS0,115200 quiet' 2>/dev/null
value=$(value_of "$f")
case $value in
*'console=ttyS0,115200'*'quiet'*) ok 'multiple arguments are all applied' ;;
*) bad "not every argument was applied: $value" ;;
esac

printf '%s\n' '# an argument already present is not duplicated'

f=$(fixture dupe 'console=tty0 quiet root=/dev/loop0p2')
rewrite "$f" 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' '' 'quiet' 2>/dev/null
value=$(value_of "$f")
n=$(printf '%s\n' "$value" | tr ' ' '\n' | grep -cx 'quiet')
if test "$n" -eq 1; then
	ok 'a repeated token appears once'
else
	bad "a repeated token appears $n times: $value"
fi

printf '%s\n' '# systemd-only arguments stay systemd-only'

f=$(fixture systemd 'console=tty0 root=/dev/loop0p2')
INIT=systemd rewrite "$f" 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' \
	' systemd.getty_auto=0 systemd.imds=no' 'console=ttyS0,115200' 2>/dev/null
value=$(value_of "$f")
case $value in
*'systemd.imds=no'*) ok 'a systemd target still gets its systemd arguments' ;;
*) bad "systemd arguments were lost: $value" ;;
esac

printf '%s\n' '# an OpenRC target never gains them'

f=$(fixture openrc 'console=tty0 root=/dev/loop0p2')
rewrite "$f" 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' '' 'console=ttyS0,115200' 2>/dev/null
value=$(value_of "$f")
case $value in
*'systemd.'*) bad "an OpenRC target gained a systemd argument: $value" ;;
*) ok 'an OpenRC target carries no systemd arguments' ;;
esac

if test "$failures" -ne 0; then
	printf 'kernel-args: %d failure(s)\n' "$failures" >&2
	exit 1
fi
printf '%s\n' 'kernel-args: OK'