#!/bin/sh

# saphira-baselayout default-grub: the packaged bootloader defaults
# must never name a root= form the kernel cannot resolve without an
# initramfs. Saphira ships no initrd and no builtin initramfs, and the
# running kernel's early_lookup_bdev resolves device paths, PARTUUID=
# and PARTLABEL= only (verified against vendored sources) - the
# filesystem UUID= and LABEL= forms need initramfs blkid and never
# boot here (Minimer 2026-11-07: every root=UUID= entry failed with
# an unmountable root, root=/dev/nvme0n1p3 booted).
#
# Hermetic: reads the tree conffile only, touches nothing.
#
# usage: default-grub.sh [DEFAULT-GRUB]
#   Defaults to the tree files/default-grub next to this test.

set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
conffile=${1:-$root/files/default-grub}

[ -f "$conffile" ] || {
	printf 'default-grub: conffile missing: %s\n' "$conffile" >&2
	exit 1
}

checks=0
ok() {
	checks=$((checks + 1))
	printf '  ok   %s\n' "$1"
}
fail() {
	printf 'default-grub: %s\n' "$*" >&2
	exit 1
}

# Filesystem UUID= root entries are unbootable without an initramfs:
# the disable flag must be set, exactly once, uncommented.
[ "$(grep -c '^GRUB_DISABLE_LINUX_UUID=true$' "$conffile")" -eq 1 ] ||
	fail 'GRUB_DISABLE_LINUX_UUID=true missing (fs UUID= root would be generated)'
ok 'GRUB_DISABLE_LINUX_UUID=true is set exactly once'

# PARTUUID stays resolvable: GPT part UUIDs are stable across disk
# reorder AND resolve in-kernel (with a device-path fallback when
# unprobable - see the 10_linux guard in the grub recipe). The flag
# must not disable PARTUUID support.
if grep -Eq '^GRUB_DISABLE_LINUX_PARTUUID=(true|yes|y|1)$' "$conffile"; then
	fail 'GRUB_DISABLE_LINUX_PARTUUID disables the stable identifier'
fi
[ "$(grep -c '^GRUB_DISABLE_LINUX_PARTUUID=' "$conffile")" -eq 1 ] ||
	fail 'GRUB_DISABLE_LINUX_PARTUUID assignment missing (explicit is better than default)'
ok 'GRUB_DISABLE_LINUX_PARTUUID does not disable partuuid support'

# No init= override, ever: an explicit init= never falls back, and a
# nonexistent path panics the kernel (proven on Egg 2026-10-22).
if grep -Eq '^[[:space:]]*(GRUB_CMDLINE_LINUX[^=]*=.*init=|GRUB_CMDLINE_LINUX_DEFAULT[^=]*=.*init=)' "$conffile"; then
	fail 'an init= override is present (banned: no fallback, panics on typo)'
fi
ok 'no init= override anywhere'

# Boot menu on the native console only: an unconditional `serial'
# command looks up port com0 and fails loudly on machines with no UART
# and no ACPI SPCR (proven: `serial port `com0' isn't found' at boot).
# Serial is per-deployment opt-in (commented example in the file).
[ "$(grep -c '^GRUB_TERMINAL_INPUT="console"$' "$conffile")" -eq 1 ] ||
	fail 'GRUB_TERMINAL_INPUT must be exactly `console` (serial is opt-in)'
ok 'GRUB_TERMINAL_INPUT is console-only'
[ "$(grep -c '^GRUB_TERMINAL_OUTPUT="console"$' "$conffile")" -eq 1 ] ||
	fail 'GRUB_TERMINAL_OUTPUT must be exactly `console` (serial is opt-in)'
ok 'GRUB_TERMINAL_OUTPUT is console-only'
if grep -Eq '^GRUB_SERIAL_COMMAND=' "$conffile"; then
	fail 'unconditional GRUB_SERIAL_COMMAND present (fails where no com0 exists)'
fi
ok 'no unconditional serial initialisation command'

printf '%s\n' "default-grub: OK ($checks checks)"
