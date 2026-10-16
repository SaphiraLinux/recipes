#!/bin/bash
# Guards the two defects that a clean image must never carry again:
#
#   1. ZFS seeded into a product profile (it was, in r14, while the
#      profile's own comment claimed ZFS was not seeded).
#   2. firstboot placed as a boot-time special: a GRUB first-boot menu,
#      or the OpenRC service placed in the sysinit runlevel so it runs
#      before essential platform setup.
#
# Asserted against the recipe source, rootless, with no build.

set -uo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
root=$(cd -- "$here/.." && pwd)
image=$root/files/saphira-image
profiles=$root/files/profiles

failures=0
ok() { printf 'ok       %s\n' "$*"; }
bad() { printf 'FAIL     %s\n' "$*" >&2; failures=$((failures + 1)); }

printf '%s\n' '# ZFS is not in any clean-image profile'

for profile in "$profiles"/*; do
	name=${profile##*/}
	# Every line of a profile is either a comment or a package intention.
	if /usr/bin/grep -q '^saphira-zfs' "$profile"; then
		bad "$name seeds a ZFS package"
	elif /usr/bin/grep -qiE '^[^#]*zfs' "$profile"; then
		bad "$name has a non-comment ZFS reference"
	else
		ok "$name is ZFS-free"
	fi
done

printf '%s\n' '# firstboot is not a boot-time special'

# The retired boot-mode target must not appear as machinery. One
# occurrence is legitimate and required: the build-time refusal check
# that greps a generated grub.cfg for it and dies. Anything else is a
# regression.
stray=$(/usr/bin/grep -n 'saphira-firstboot\.target' "$image" | /usr/bin/grep -v 'grep -cE' || true)
if test -n "$stray"; then
	printf 'FAIL     the image tool references saphira-firstboot.target as machinery:\n%s\n' "$stray" >&2
	failures=$((failures + 1))
else
	ok 'no saphira-firstboot.target machinery (only the refusal check)'
fi

if /usr/bin/grep -q "first-boot setup" "$image" &&
	! /usr/bin/grep -q 'grep -cE' "$image"; then
	bad 'the image tool appears to write a first-boot GRUB entry'
else
	ok 'no first-boot GRUB menu is generated'
fi

if /usr/bin/grep -q 'runlevels/sysinit/saphira-firstboot' "$image"; then
	bad 'firstboot is still placed in the sysinit runlevel'
else
	ok 'firstboot is not in the sysinit runlevel'
fi

if /usr/bin/grep -q 'runlevels/boot/saphira-firstboot' "$image"; then
	ok 'firstboot is placed in the boot runlevel'
else
	bad 'firstboot is not placed in the boot runlevel'
fi

# The systemd gate must sit on multi-user.target (the default target),
# never on basic.target: the unit carries systemd's default dependencies
# and is therefore ordered after basic.target, so gating basic.target
# would pull the wizard forward, ahead of platform setup.
if /usr/bin/grep -q 'basic\.target\.d' "$image"; then
	bad 'the systemd gate still targets basic.target'
else
	ok 'the systemd gate is not on basic.target'
fi

if /usr/bin/grep -q 'multi-user\.target\.d' "$image"; then
	ok 'the systemd gate is on multi-user.target'
else
	bad 'the systemd gate is not on multi-user.target'
fi

printf '%s\n' '# the shipped unit keeps default dependencies'

unit=$root/../saphira-baselayout/files/saphira-firstboot.service
if test ! -r "$unit"; then
	printf 'unit not readable, skipping: %s\n' "$unit" >&2
else
	if /usr/bin/grep -q '^DefaultDependencies=no' "$unit"; then
		bad 'the firstboot unit disables default dependencies (would run before basic.target)'
	else
		ok 'the firstboot unit keeps systemd default dependencies'
	fi
	if /usr/bin/grep -q 'saphira-fhs-converge' "$unit"; then
		ok 'the firstboot unit is ordered after the layout migration'
	else
		bad 'the firstboot unit does not order after saphira-fhs-converge'
	fi
fi

printf '%s\n' '# kernel arguments belong to their target'

# The packaged default is init-neutral. A systemd-only argument there is
# target leakage: meaningless on OpenRC, and misleading in /proc/cmdline.
default_grub=$root/../saphira-baselayout/files/default-grub
if test ! -r "$default_grub"; then
	printf 'default-grub not readable, skipping: %s\n' "$default_grub" >&2
elif /usr/bin/grep -E '^GRUB_CMDLINE_LINUX=.*systemd\.' "$default_grub" >/dev/null; then
	bad 'the packaged GRUB_CMDLINE_LINUX carries a systemd-only argument'
else
	ok 'the packaged GRUB_CMDLINE_LINUX is init-neutral'
fi

# ...and the image adds them per target instead.
if /usr/bin/grep -q 'INIT.*=.*systemd.*getty_opt=.*systemd.imds=no' "$image"; then
	ok 'systemd kernel arguments are added for systemd targets only'
else
	bad 'the image tool must add systemd.imds=no for systemd targets'
fi

if test "$failures" -ne 0; then
	printf 'clean-image-guards: %d failure(s)\n' "$failures" >&2
	exit 1
fi
printf '%s\n' 'clean-image-guards: OK'