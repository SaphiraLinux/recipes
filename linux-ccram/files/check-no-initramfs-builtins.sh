#!/bin/sh
# check-no-initramfs-builtins.sh - no-initramfs builtin policy gate.
#
# Sourced by saphira-kernel recipe_build() after `make olddefconfig` and by
# builder tests. Pure config-file logic over an explicit path argument (no
# builder globals), so the policy is unit-testable without compiling a kernel.
#
# Policy: Saphira ships without an initramfs, therefore every hardware,
# filesystem and console driver needed before the root mount -- and for
# baseline local recovery -- must be built in (=y). A symbol that drifts to
# =m is exactly as fatal as one that vanishes: a module living on the root
# filesystem cannot mount the root filesystem. Both fail this gate.
#
# The list below is the reconstruction of the original builtin set (the
# EXT4_FS/VIRTIO_BLK/NVME/SCSI/EFI/EFI_STUB core stated when initramfs
# support was enabled as a capability), extended for every supported boot
# target: BIOS/VGA, UEFI framebuffer (OVMF/QXL VMs, physical UEFI boxes),
# serial, and netconsole. Audio and the like stay modules deliberately;
# this gate covers boot, video and network only.
#
# Defensive shell: every failure prints `no-initramfs-builtins: ...` and
# the entry point returns non-zero (callers run under `set -eu`).

nib_die()
{
	printf 'no-initramfs-builtins: %s\n' "$*" >&2
	return 1
}

# Required builtins, grouped by area. Keep sorted within groups; the
# trailing comment on each group states what breaks without it.
nib_required_symbols()
{
	# Root block/storage path (SATA/NVMe/virtio; VMD covers Intel
	# RST-mode remap on N100 and similar boards).
	printf '%s\n' ATA BLK_DEV_NVME BLK_DEV_SD DEVTMPFS EXT4_FS \
		NVME_CORE SATA_AHCI SCSI VIRTIO_BLK VIRTIO_PCI VMD
	# USB mass storage / recovery sticks.
	printf '%s\n' USB_STORAGE USB_UAS USB_XHCI_HCD
	# Disk layout and EFI boot.
	printf '%s\n' EFI_PARTITION EFI_STUB
	# Local console: VGA text (BIOS), EFI framebuffer + fbcon (UEFI,
	# where no VGA text mode exists), 8250 serial.
	printf '%s\n' EARLY_PRINTK FB FB_EFI FRAMEBUFFER_CONSOLE \
		SERIAL_8250 SERIAL_8250_CONSOLE SERIAL_EARLYCON SYSFB \
		SYSFB_SIMPLEFB VGA_CONSOLE VT VT_CONSOLE
	# KMS for virtio-vga UEFI guests (handoff target of the fbcon above).
	printf '%s\n' DRM DRM_VIRTIO_GPU
	# Network for the supported appliance hardware plus netconsole
	# recovery (E1000E/IGB/IGC cover Intel desktop/server/N100
	# 2.5GbE; R8169 the common Realtek; VIRTIO_NET the VMs).
	printf '%s\n' E1000E IGB IGC NETCONSOLE R8169 VIRTIO_NET
	# Initramfs capability: required on every kernel line because ZFS
	# may later become a root filesystem. RD_ZSTD is the decompressor
	# saphira-mkinitramfs produces; RD_GZIP is carried for compatibility.
	printf '%s\n' BLK_DEV_INITRD RD_GZIP RD_ZSTD
}

# nib_symbol_state CONFIGFILE SYMBOL - print y, m, n or absent.
nib_symbol_state()
{
	if grep -q "^CONFIG_$2=y$" "$1"; then
		printf 'y\n'
	elif grep -q "^CONFIG_$2=m$" "$1"; then
		printf 'm\n'
	elif grep -q "^# CONFIG_$2 is not set$" "$1"; then
		printf 'n\n'
	else
		printf 'absent\n'
	fi
}

# check_no_initramfs_builtins CONFIGFILE [LABEL] - assert every required
# symbol is exactly =y. Reports all offenders, then returns non-zero.
check_no_initramfs_builtins()
{
	[ "$#" -ge 1 ] || { nib_die "usage: check_no_initramfs_builtins CONFIGFILE [LABEL]"; return 1; }
	[ -f "$1" ] || { nib_die "no config file at $1"; return 1; }
	label="${2:-$1}"
	fails=0
	for sym in $(nib_required_symbols); do
		state=$(nib_symbol_state "$1" "$sym")
		if [ "$state" != "y" ]; then
			printf 'no-initramfs-builtins: %s: CONFIG_%s is %s, must be =y\n' \
				"$label" "$sym" "$state" >&2
			fails=$((fails + 1))
		fi
	done
	if [ "$fails" -ne 0 ]; then
		nib_die "$label: $fails required builtin(s) not =y (see above)"
		return 1
	fi
	printf 'no-initramfs-builtins: %s: all required symbols =y\n' "$label"
}
