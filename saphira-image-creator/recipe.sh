#!/bin/sh

# r4: bios-saphira/bios-saphirad product targets (0.2.1 seeds);
# minimal-* kernel bare name -> saphira-kernel-7.2.3 (the bare name
# died with the per-kver split; every matrix target was unbuildable).
# r3: ship the 0.2.1 base profiles (saphira-openrc, saphirad-systemd):
# the exact Saphira/SaphiraD seed intentions with product-identity
# packages, no chrony/bind, kernel pinned by per-kver line name.
# r2: ship files/services.d, the package -> init services mapping, so a
# package may declare the service name it provides instead of the image
# builder assuming service-name == package-name. saphira-packager ships
# saphira-build; naming the package in a profile previously enabled nothing,
# silently. The mapping is data beside the profiles (a profile still lists
# only package intentions, per saphira-profiles(5)) and is optional.
pkgname=saphira-image-creator
pkgver=0.1
pkgrel=39
# r39: layout options (--boot-size honored on ext4 with a separate
# /boot, --swap-size with swap-last partitioning and fstab, --earlyfw
# strict opt-in with a persistent marker), computed partition
# numbering (no hardcoded positions), mkswap prerequisite. Payload
# change (tool).
# r38: installer-appliance network default as tool data (not a second
# owner of saphira-network's /usr/lib path): the appliance profile
# excludes saphira-network, so the image writes this copy to
# /etc/systemd/network for that profile only. Payload change (data).
# r37: ESP fstab nofail pass 0, settle mask on the appliance.
# Payload change (tool).
# r36: ESP fstab append, disk ESP fix, empty root + SSH guard for the
# creator appliance, systemd installer appliance (unit enablement,
# firstboot exemptions, marker swap). Payload change (tool).
# r35: boot_device_for covers hybrid (p1 bios-boot): hybrid image
# r34: usb-installer-appliance hybrid/openrc target (appliance-only
# hybrid exception), installer-appliance init branch, firstboot
# exemption for that profile. Payload change (matrix, tool).
# r33: usb-creator appliance target (BIOS/openrc menu appliance) plus
# r32: early-firmware generation in image/disk finalize (2026-10-23):
# shared generate_earlyfw helper runs before grub-mkconfig on both
# paths (hooks never fire under --no-scripts assembly). Payload
# change (tool).
# r31: product-specific default hostname (2026-10-23): unnamed
# systemd installs identify as saphirad, OpenRC as saphira, via
# default_hostname(). Payload change (tool + man page).
# r30: hoist shared helpers to top level (2026-10-23, SEV boot
# defect): fix_kernel_cmdline, prepare_installer,
# build_installer_initramfs and finalize_bootloader were defined
# inside cmd_build, so they registered only when the image path ran
# and every disk install died with "command not found" at the first
# shared call while image builds worked. Locked by the register-on-
# parse check in saphira-packager/tests/image-creator.sh. Payload
# change (tool).
# r29: wipe old signatures before partitioning on the disk path
# (2026-10-23): sfdisk rewrites the table but stale superblocks/RAID
# metadata survive to confuse probing or stall for confirmation.
# wipefs -a runs after the typed confirmation, whole confirmed device
# only; wipefs joins the pre-flight tool checks. Payload change.
# r28: install-to-disk repairs (2026-10-23, proven against /dev/sda):
# util-linux blockdev takes `command device' with no `--' separator
# (validate_device probed sizes wrong on every disk -- constrain the
# spelling to /dev/* instead); the disk path never set PLAN_BUFFER so
# previews printed empty plans, and the piped preview swallowed plan
# failures. Payload change (tool).
# r27: configurable ESP/root sizing (2026-10-23): --esp-size from the
# 64/128/256/512/768/1024 MiB ladder (default 64, FAT32 always),
# --root-size for an exact root, --allocate on the install-to-disk
# path. Refusals (not silent resizes) for over-budget combinations,
# hoisted out of the piped plan emitter where die was swallowed
# (proven: an 80M plan printed "too small" and exited 0). Payload
# change (tool + man page).
# r26: hybrid usb-installer target (bios-boot + ESP + installer root,
# both GRUB loaders, ram-mode initramfs, menu service on, firstboot
# off). One medium boots both firmwares into the installer menu; the
# installed machine's init is chosen there, never here.
# r25: ESP 512M(doc)/256M(actual) -> 64 MiB. The old comment claimed
# 512 MiB while the constant staged 524288 sectors (256 MiB); both are
# gone. 64 MiB holds the ~1.5 MiB EFI payload (GRUB only; kernel and
# initramfs stay in /boot, proven by the Minimer reference layout) forty
# times over, sits at twice the FAT32 cluster-count floor that rules
# out 32 MiB, and brings UEFI images inside the 500 MB installer
# budget. FAT32 formatting and firmware boot of the smaller ESP are
# Hatchling-verified, not assumed.
# r24: install-to-disk. The same engine (partition plan, saphira-install,
# init preparation, PARTUUID bootloader, measurement) installs onto a
# physical disk instead of an image file: same functions, whole-device
# backing, grub-install to the disk, no loop detach, no qcow2 convert.
# Safety is structural, not advisory: no default device, no discovery,
# mounted/swapped/boot disks refused outright, the complete plan always
# printed first, --preview stops before anything is touched, and a real
# run requires typing the device path back. On failure the disk is
# unmounted and left as-is, never wiped by the error path. UEFI uses
# the --removable fallback path (no NVRAM writes); efibootmgr stays a
# deliberate follow-up.
# r23: profiles move to the single authoritative tree in
# saphira-install-tools (/usr/share/saphira/profiles). This package
# ships the target matrix and the service mapping only; profile
# intentions are validated where they live (install-tools recipe_build)
# and the tool reads the shared tree (source tree, installed package,
# or SAPHIRA_IMAGE_PROFILES override). No payload change beyond the
# moved data: the same profiles resolve for every matrix target.
# r22: systemd-only kernel arguments are added per target, not shipped in
# the init-neutral packaged default. systemd.imds=no (with
# systemd.getty_auto=0) now goes on the SaphiraD kernel line only; an
# OpenRC target carries neither. Previously systemd.imds=no lived in
# GRUB_CMDLINE_LINUX for every image, where it was meaningless and read
# as target leakage in /proc/cmdline.
# r21: clean images, and the boot order firstboot actually wants.
# ZFS is out of both product profiles. It was seeded in r14, which put
# saphira-zfs-7.2.3 and its userspace into every clean image while the
# profile's own comment claimed ZFS was not seeded. A clean image
# carries no filesystem driver the distribution does not use; root on
# ZFS is a deliberate flavour, built and shipped as such. The
# saphira-zfs-* recipes stay in the catalogue for that flavour.
# OpenRC placement moved from sysinit to the boot runlevel. sysinit is
# devfs, sysfs, dmesg and cgroups, so a wizard placed there appeared
# while ordinary boot messages were still pending and raced device
# discovery for its interface list - the "wizard halfway through boot"
# complaint. The wizard now runs in the boot runlevel, ordered after
# the boot-level services its depend() lists (modules, filesystem work,
# seedrng for entropy, console encoding, the FHS convergence), so the
# sequence is bootloader, kernel, real root, init, sysinit, boot-level
# platform work, wizard, and only then the default runlevel with gettys
# and sshd. Blocking its own runlevel still gives it exclusive console
# ownership, and runlevels are strictly ordered so nothing interleaves.
# The interleaved prompts that motivated the old placement came from
# concurrent starts inside one runlevel, which `after` dependencies
# prevent - the runlevel itself was never the problem.
# systemd gate moved from basic.target to multi-user.target (the
# default target), paired with the unit carrying systemd's default
# dependencies: the unit is therefore ordered AFTER basic.target, i.e.
# after essential platform setup, while login, gettys and operational
# services still wait for it. Gating basic.target did the opposite - it
# pulled the wizard forward, ahead of the platform work.
# Still no firstboot boot mode anywhere: one GRUB entry plus its
# recovery options, no initrd, and the build still refuses any
# firstboot artefact in the generated grub.cfg.
# r20: normal-boot firstboot gate (no boot mode anywhere): prepare_init
# writes three drop-ins on systemd targets - basic.target Wants+After
# firstboot (holds the whole operational transaction while the marker
# exists, releases on condition-skip), nftables After firstboot (its
# DefaultDependencies=no escapes the gate otherwise), firstboot After
# fhs-converge (Before=sysinit does not order it before the wizard).
# Proven live on a disposable copy before shipping; argued from the
# shipped unit graph, not assumption.
# r19: remove the firstboot GRUB boot-mode architecture entirely (the
# r17 menuentry clone + marker-conditional default + systemd.unit=
# selection was an unrequested design: firstboot is init-level, never
# a second boot mode). finalize_bootloader now only stabilizes root=
# (strip every build-loop token, leave exactly one root=PARTUUID) and
# REFUSES any firstboot artefact in grub.cfg. PARTUUID/loop work kept.
# r18: comment sync only (no serial getty anywhere: Saphira ships none,
# so firstboot no longer creates one; VGA gettys cover login).
# r17: bootloader finalization, root= stabilization only (see r19):
# strip every build-host root=/dev/loopNp2 token from all linux lines
# (grub-mkconfig probes the build loop; the leak showed in /proc/cmdline
# and reads as a release defect) leaving exactly one root=PARTUUID.
# r16: firstboot runs first in the sysinit runlevel (blocking, with
# keyword -timeout in its init script), not detached in boot: the
# interactive wizard now owns the console exclusively and every normal
# service necessarily starts after setup completes (proven: boot output
# interleaved with password/account/network prompts).
# r15: mount the ESP after the install, not before (saphira-install
# refuses a non-empty target and even a fresh empty FAT trips it -
# UEFI builds died there; grub-install is the only step needing it).
# r14: release contents - saphira-zfs-7.2.3 in both product profiles
# (release kernel + matching ZFS ship together) and uefi-saphira /
# uefi-saphirad product targets.
# r13: mask never-auto-start units on systemd targets (acpid,
# saphira-network: a first-boot path enabled them despite the
# services-off exclusion) + build-time assert that exclusions hold.
# r12: systemd.getty_auto=0 on systemd targets (the getty
# generator autospawns a serial getty per kernel console and HUPs
# the firstboot wizard fighting it for /dev/console).
# r11: images ship no serial getty (firstboot owns the port
# until it completes, then creates the login prompt itself).
# r10: mask upstream systemd-firstboot.service in systemd images
# (it fires on missing machine-id and would prompt on the same
# console as saphira-firstboot, which owns first boot).
# r9: services-off matcher fix (skip list flattened to spaces: the
# space-wrapped case match never fired across newline boundaries,
# so nothing was ever skipped - proven by an SD image carrying
# saphira-network.service despite the exclusion file).
# r8: services-off.d exclusions (units never auto-enabled per init:
# acpid + saphira-network on systemd, where logind and networkd own
# those roles), firstboot invocation in prepare_init (both inits),
# networkd units in the systemd infra set, and the export subcommand
# for distributable bootstrap rootfs archives.
# r7: deployment-stable kernel cmdline (fix_kernel_cmdline, before
# grub-mkconfig): strip build-loop root= (grub probes the mounted
# build root - the guest panics on /dev/loop0p2) and any init=
# (both payloads ship a real /sbin/init, the kernel default;
# the packaged default wrongly forced systemd even on OpenRC),
# appending root=PARTUUID=<gpt-guid> which is stable across vda/sda
# and needs no initramfs (proven: grub-booted guest idle-halted).
# r6: services.d mapping for openssh -> sshd (same name-mismatch
# class as saphira-packager -> saphira-build; without it a profile
# naming openssh enables nothing and the image ships sshd stopped).
# r5: image-owned platform enablement (prepare_init, not profiles):
# openrc boot runlevel gains saphira-fhs-converge + serial getty
# instance (profiles never enumerate base plumbing, and the 0.2.1
# guest proved the alias is never converged without it); systemd
# default.target fixed to the real multi-user.target (was a dangling
# /lib/...wants link) with infra units enabled (fhs-converge, sshd,
# serial-getty@ttyS0); new --netconf IFACE:MODE writes proof/test
# network stanzas (empty default writes nothing - product unchanged).
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Saphira bootable image creator: BIOS/UEFI x OpenRC/systemd target matrix over the canonical saphira-install assembler'
license='BUSL-1.1'
origin=saphira-image-creator
repo=saphira
url=https://saphira.vm2.uk/

# The creator ORCHESTRATES; it does not assemble. saphira-install owns the
# mounted-target installation and saphira-assemble-rootfs owns the rootfs
# assembly and the identity replay, so those are hard dependencies: the tool
# refuses to substitute its own path when they are absent.
#
# util-linux supplies sfdisk and losetup on the HOST that builds the image.
# e2fsprogs supplies mkfs.ext4. dosfstools supplies mkfs.vfat, which a
# uefi-* target cannot be built without. grub supplies grub-install and
# grub-mkconfig. qemu is optional: it is needed only for a .qcow2 output.
depends="
	saphira-install-tools
	util-linux
	e2fsprogs
	dosfstools
	grub
"
makedepends=""

recipe_build()
{
	# Every target must name a profile that exists and a supported
	# boot/init pair. A matrix row naming a profile that was renamed
	# would otherwise fail only at image-build time. Profile INTENTIONS
	# (every bare name is a real recipe, every @-include resolves) are
	# validated where the profiles live, in
	# saphira-install-tools/recipe.sh.
	local name boot init profile
	while read -r name boot init profile; do
		case $name in ''|'#'*) continue ;; esac
		case $boot in bios|uefi|hybrid) ;; *) echo "ERROR: target $name has boot=$boot" >&2; return 1 ;; esac
		case $init in openrc|systemd) ;; *) echo "ERROR: target $name has init=$init" >&2; return 1 ;; esac
		if [ "$boot" = hybrid ] && [ "$init" != systemd ]; then
			echo "ERROR: target $name: hybrid boot requires the systemd installer environment" >&2
			return 1
		fi
		[ -n "$profile" ] || {
			echo "ERROR: target $name names no profile" >&2
			return 1
		}
		# Profiles live in the single shared tree (install-tools);
		# a matrix row naming a profile that is not there fails here,
		# not at image-build time.
		[ -f "$SAPHIRA_RECIPE_ROOT/saphira-install-tools/files/profiles/$profile" ] || {
			echo "ERROR: target $name names a missing shared profile: $profile" >&2
			return 1
		}
	done < "$RECIPE_DIR/files/targets"
	# Shell and man page must be syntactically valid before they ship.
	/bin/sh -n "$RECIPE_DIR/files/saphira-image" || {
		echo "ERROR: saphira-image does not parse" >&2
		return 1
	}
	cmp -s "$SAPHIRA_RECIPE_ROOT/saphira-network/files/systemd-network/80-saphira-wired-dhcp.network" \
		"$RECIPE_DIR/files/systemd-network/80-saphira-wired-dhcp.network" || {
		echo "ERROR: appliance network default drifted from saphira-network" >&2
		return 1
	}
}

recipe_install()
{
	install -D -m 0755 "$RECIPE_DIR/files/saphira-image" \
		"$PKGDEST/usr/bin/saphira-image"
	install -D -m 0644 "$RECIPE_DIR/files/targets" \
		"$PKGDEST/usr/share/saphira/image/targets"
	# Appliance-local wired DHCP default. This is TOOL DATA, not a
	# second package owner of saphira-network's /usr/lib path: the
	# image installs it to /etc/systemd/network for the appliance
	# profile only. Content must match saphira-network's default.
	install -D -m 0644 "$RECIPE_DIR/files/systemd-network/80-saphira-wired-dhcp.network" \
		"$PKGDEST/usr/share/saphira/image/systemd-network/80-saphira-wired-dhcp.network"
	# Package -> init services mapping. OPTIONAL data: absent means every
	# service is named after its package, which is the normal case. It
	# exists because that assumption is not universal - saphira-packager
	# ships saphira-build - and the assumption failing enabled nothing,
	# silently.
	install -d -m 0755 "$PKGDEST/usr/share/saphira/image/services.d"
	for svc in "$RECIPE_DIR"/files/services.d/*; do
		[ -f "$svc" ] || continue
		install -m 0644 "$svc" \
			"$PKGDEST/usr/share/saphira/image/services.d/${svc##*/}"
	done
	# Init-scoped enablement exclusions (services-off.d/<init>):
	# units never auto-enabled on that init even when profiled.
	# Same optional-data contract: an absent file skips nothing.
	if [ -d "$RECIPE_DIR/files/services-off.d" ]; then
		install -d -m 0755 "$PKGDEST/usr/share/saphira/image/services-off.d"
		for off in "$RECIPE_DIR"/files/services-off.d/*; do
			[ -f "$off" ] || continue
			install -m 0644 "$off" \
				"$PKGDEST/usr/share/saphira/image/services-off.d/${off##*/}"
		done
	fi
	install -D -m 0644 "$RECIPE_DIR/files/saphira-image.8" \
		"$PKGDEST/usr/share/man/man8/saphira-image.8"
	install -D -m 0644 "$RECIPE_DIR/files/licenses/LICENSE" \
		"$PKGDEST/usr/share/licenses/saphira-image-creator/LICENSE"
	# The tool resolves its data beside itself, so the payload must carry
	# the matrix. Profiles come from the shared tree (saphira-install-tools
	# dependency), asserted rather than assumed: a missing matrix makes
	# every subcommand fail at runtime.
	for p in usr/share/saphira/image/targets usr/bin/saphira-image; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: saphira-image-creator payload is missing $p" >&2
			return 1
		}
	done
	# Every declared mapping must be non-empty, or it would silently enable
	# nothing and reintroduce the defect it exists to fix.
	for svc in "$PKGDEST"/usr/share/saphira/image/services.d/*; do
		[ -f "$svc" ] || continue
		[ -s "$svc" ] || {
			echo "ERROR: empty services.d mapping would enable nothing: ${svc##*/}" >&2
			return 1
		}
	done
}
