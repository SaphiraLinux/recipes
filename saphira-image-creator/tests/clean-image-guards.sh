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
# Profiles live in the single shared tree (saphira-install-tools); the
# guards run against the authority, not a copy.
profiles=$root/../saphira-install-tools/files/profiles

failures=0
ok() { printf 'ok       %s\n' "$*"; }
bad() { printf 'FAIL     %s\n' "$*" >&2; failures=$((failures + 1)); }

printf '%s\n' '# ZFS is not in any clean-image profile'

# Exempt by design: the image-creator appliance exists to create ZFS
# systems, so its profile and the role-zfs layer carry the kmod and
# userspace deliberately. The installer appliance is the same story
# (dedicated installer, ZFS creation target). Every other profile
# stays ZFS-free.
zfs_exempt="image-creator-appliance image-installer-appliance role-zfs"
for profile in "$profiles"/*; do
	name=${profile##*/}
	case " $zfs_exempt " in
	*" $name "*) ok "$name carries ZFS deliberately (creator tooling)" ;;
	*)
	# Every line of a profile is either a comment or a package intention.
	if /usr/bin/grep -q '^saphira-zfs' "$profile"; then
		bad "$name seeds a ZFS package"
	elif /usr/bin/grep -qiE '^[^#]*zfs' "$profile"; then
		bad "$name has a non-comment ZFS reference"
	else
		ok "$name is ZFS-free"
	fi
		;;
	esac
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
	# Transaction separation (2026-10-23): fhs-converge completes
	# before sysinit.target while firstboot starts after basic.target,
	# so transaction order already separates them by a full boot phase.
	# A direct edge from this multi-user-gated unit back into a sysinit
	# unit adds no ordering and is the shape that turns healthy
	# orderings into reported transaction cycles: it must stay out.
	if /usr/bin/grep -q 'saphira-fhs-converge' "$unit"; then
		bad 'the firstboot unit names saphira-fhs-converge (cross-transaction edge)'
	else
		ok 'the firstboot unit leaves the layout migration to transaction order'
	fi
fi

printf '%s\n' '# kernel arguments belong to their target'

# The packaged default is init-neutral. A systemd-only argument there is
# target leakage: meaningless on OpenRC, and misleading in /proc/cmdline.
default_grub=$root/../saphira-baselayout/files/default-grub
packaged_cmdline=
if test -r "$default_grub"; then
	packaged_cmdline=$(/usr/bin/sed -n 's/^GRUB_CMDLINE_LINUX="\(.*\)"$/\1/p' "$default_grub")
fi
if test ! -r "$default_grub"; then
	printf 'default-grub not readable, skipping: %s\n' "$default_grub" >&2
elif test -z "$packaged_cmdline"; then
	bad 'the packaged GRUB_CMDLINE_LINUX is missing or unparseable'
elif /usr/bin/grep -E '^GRUB_CMDLINE_LINUX=.*systemd\.' "$default_grub" >/dev/null; then
	bad 'the packaged GRUB_CMDLINE_LINUX carries a systemd-only argument'
# SEV1 2026-10-22: the systemd\. check above is evaded by
# init=/usr/lib/systemd/systemd (no dot after "systemd"), which reached a
# live grub.cfg and panicked Egg - explicit init= never falls back. The
# packaged default must carry no init= token at all.
elif case " $packaged_cmdline " in *' init='*) true ;; *) false ;; esac; then
	bad 'the packaged GRUB_CMDLINE_LINUX carries an init= override (bootloader must never name the init implementation)'
else
	ok 'the packaged GRUB_CMDLINE_LINUX is init-neutral'
fi

# ...and the image adds them per target instead.
if /usr/bin/grep -q 'INIT.*=.*systemd.*getty_opt=.*systemd.imds=no' "$image"; then
	ok 'systemd kernel arguments are added for systemd targets only'
else
	bad 'the image tool must add systemd.imds=no for systemd targets'
fi

printf '%s\n' '# boot-time accounting is enabled, never baked'

# Export must not capture boot state: utmp/wtmp hold the previous
# boot's records (the writer appends per btime, so a baked file
# would report a stale boot), and a stale systemd random-seed makes
# coreutils fall back to image age instead of boot time (the 50-day
# Egg uptime scare: no BOOT_TIME record is ever readable on musl,
# so the seed mtime wins whenever the file exists).
for baked in "var/run/utmp" "var/log/wtmp" "var/lib/systemd/random-seed"; do
	if /usr/bin/grep -q "exclude='./$baked'" "$image"; then
		ok "export excludes $baked"
	else
		bad "export does not exclude $baked"
	fi
done

# The recorder must run in the boot runlevel (before gettys), on
# both inits, guarded by presence like the other platform plumbing.
if /usr/bin/grep -q 'runlevels/boot/saphira-utmp-boot' "$image"; then
	ok 'utmp-boot is placed in the boot runlevel'
else
	bad 'utmp-boot is not placed in the boot runlevel'
fi
if /usr/bin/grep -q 'saphira-utmp-boot.service' "$image"; then
	ok 'utmp-boot is enabled on systemd targets'
else
	bad 'utmp-boot is not enabled on systemd targets'
fi

# The unit keeps systemd default dependencies: it must run after
# local filesystem availability, not before basic.target.
unit=$root/../saphira-utmp/files/saphira-utmp-boot.service
if test ! -r "$unit"; then
	printf 'unit not readable, skipping: %s\n' "$unit" >&2
else
	if /usr/bin/grep -q '^DefaultDependencies=no' "$unit"; then
		bad 'the utmp-boot unit disables default dependencies'
	else
		ok 'the utmp-boot unit keeps systemd default dependencies'
	fi
fi

# The OpenRC service runs after the layout migration it writes
# through, in the boot runlevel before ordinary services.
initd=$root/../saphira-utmp/files/saphira-utmp-boot.initd
if test ! -r "$initd"; then
	printf 'initd not readable, skipping: %s\n' "$initd" >&2
else
	if /usr/bin/grep -q 'after saphira-fhs-converge' "$initd"; then
		ok 'utmp-boot is ordered after the layout migration'
	else
		bad 'utmp-boot does not order after saphira-fhs-converge'
	fi
	if /usr/bin/grep -q 'before \*' "$initd"; then
		ok 'utmp-boot runs before ordinary services'
	else
		bad 'utmp-boot has no before * ordering'
	fi
fi

if test "$failures" -ne 0; then
	printf 'clean-image-guards: %d failure(s)\n' "$failures" >&2
	exit 1
fi
printf '%s\n' 'clean-image-guards: OK'