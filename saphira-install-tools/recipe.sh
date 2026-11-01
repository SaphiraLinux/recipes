#!/bin/sh

pkgname=saphira-install-tools
pkgver=0.1
pkgrel=42
# r42: minimal-openrc/minimal-systemd gain procps-ng (minimer live gap:
# nothing owned /bin/ps in the installer profiles). Manifest refreshed.
# r41: same mount-aware target acceptance in saphira-bootstrap
# (its own emptiness gate refused the mounted /boot one layer below
# saphira-install, aborting every separate-/boot assembly after the
# installer gate had already passed). New bootstrap-target-emptiness
# suite, gated in recipe_build like the install one. Payload change.
# r40: saphira-install target acceptance is mount-aware: separately
# mounted filesystems below the target (the installer's own /boot)
# are the caller's scaffolding, not content, for both the
# empty-target refusal and the --reinstall wipe (which no longer
# tries to rm -rf a live mountpoint). Without this every
# --boot-size install died at assembly and --reinstall died
# clearing. Payload change (tool + man page + test).
# r39: minimal profiles gain vim, saphira-network and dhcpcd (both
# inits); supplied --root-password spends the firstboot marker again.
# Payload change (profiles + tool).
# r38: installed-package manifest - assemble-rootfs merges every
# installed package into target /etc/apk/world (intentions only
# left everything prunable, proven by a del that removed the package
# manager itself). Payload change (tool).
# r37: creator menu Setup Network first, HTTPS repository gate, fixed
# four-product destination catalog (BIOS/UEFI x Saphira/SaphiraD),
# ping-gated writes (3s per family), ordered tty1 unit with TERM. The
# engine target matrix is not exposed; the appliance boots straight to
# the menu and networking is operator-chosen. A repeatedly failing menu
# falls back to a local tty1 recovery console; the ordinary installer
# menu stays masked on this appliance.
# Payload change.
# r36: installer appliance becomes a passwordless creator menu.
# Destination installs stay locked-root for ordinary firstboot; the
# menu no longer asks for, passes, or copies passwords, network, or
# DNS. Adds the creator-menu systemd unit. Payload change.
# r35: fstype-aware genfstab (vfat nofail pass 0, root unchanged).
# Payload change.
# r34: udev in both appliance profiles (by-id needs the daemon).
# Payload change.
# r33: default TERM=linux in the creator menu (dialog dies silent
# without TERM in the boot runlevel). Payload change.
# r32: image-installer-appliance profile (dedicated installer with
# network backend). Payload change.
# r31: image-creator appliance tooling: creator menu + openrc service +
# man page, image-creator-appliance and role-zfs profiles, man entries.
# Payload change.
# r30: early-boot firmware set (2026-10-23): saphirad-systemd gains
# intel-ucode + i915/intel/network firmware + the earlyfw generator;
# usb-installer gains intel-ucode + generator. Payload change.
# r29: usb-installer profile takes linux-firmware-full (2026-10-23):
# bare linux-firmware is licence evidence only since the family
# split; unknown target hardware needs every family.
# r28: product-specific installer defaults (2026-10-23): menu hostname
# defaults to saphirad-new on systemd targets, saphira-new on OpenRC;
# both product profiles ship sudo (wheel NOPASSWD needs it). Payload
# change (menu + profiles).
# r27: menu console selection honours saphira.install_tty= on the
# kernel cmdline (serial installs), with INSTALL_TTY env first and
# /dev/console last. Serial operation is required, not a debug path.
# r26: USB installer composition pieces (installer-entrypoint +
# installer-initramfs.conf + usb-installer profile): the ram-mode
# entrypoint mounts the payload by label and hands over; the conf
# names it for saphira-mkinitramfs; the profile is installer
# userspace + boot kernel + firmware (never the installed product).
# r25: v0 guided installer menu (saphira-install-menu + tty1 service +
# man page + suite) and its installer-profile closure (dialog,
# saphira-image-creator backend). The menu chooses, the planner
# validates, the existing engine writes; nothing here partitions.
# r24: installer profile carries one creation tool per offered root
# (xfsprogs, lvm2, saphira-zfs-userspace alongside e2fsprogs).
# btrfs stays out: kernel-builtin but never an offered root.
# r23: declarative installation planner (saphira-install-plan +
# manifest format + example + suite). One strict KEY=VALUE manifest
# describes firmware/init/rootfs/layout/role/repo/identity for the USB
# installer, the future pre-boot menu and image-creator alike;
# validation refuses unknown keys, duplicates, secrets and unprovable
# kernel filesystem support. Execution stays where it is (planner
# writes nothing).
# r22: single authoritative profile tree. The product and role profiles
# lived in saphira-image-creator's own files/profiles/ while the base,
# init and installer profiles lived here, with two kernels (bare
# saphira-kernel, disabled, versus the pinned 7.2.3 line) and two
# meanings of saphira-openrc. All product and role profiles move here;
# the kernel is pinned to saphira-kernel-7.2.3 everywhere; the thin
# saphira-openrc/saphira-systemd compositions are retired (superseded
# by the products of the same names). saphira-image-creator consumes
# this tree now; it ships no profiles of its own.
# r21: assembly writes /etc/.updated LAST (factory-state stamp): fresh
# targets skip first-boot ConditionNeedsUpdate units (notably
# systemd-hwdb-update, whose database ships prebuilt) instead of
# redoing that work during initial configuration, while later package
# upgrades still refire them exactly once.
# r20: replay caps.d fragments at assembly (ensure-caps --root):
# --no-scripts installs never converge file capabilities and APK
# records no xattr state, so capability-needing payloads (ping)
# installed dead - proven by non-root ping failing in 0.2.1.
# r19: two assembly defects proven by the 0.2.1 clean-root builds:
#   bootstrap cds into the empty target before invoking apk (apk
#   resolves a token against CWD first, so any profile intention
#   sharing its name with a CWD directory died "X: Is a directory");
#   the assembler skips accounts.d/*.legacy sidecars in the identity
#   replay (ensure-identity loads them itself via $FRAGMENT.legacy;
#   feeding dbus.legacy as a fragment killed systemd assembly).
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Saphira image/install tooling (bootstrap, chroot, genfstab, assembler, installer, imager) and install profiles'
license='BUSL-1.1'
origin=saphira-install-tools
repo=saphira
url=https://saphira.vm2.uk/

# Payload vendored from the live Egg install (the generation-zero Stage4
# mount is retired); bytes pinned below. r1 is the ABI migration:
#   depends: akadata-base-abi -> saphira-base-abi
#   profiles/base: akadata-base-abi -> saphira-base-abi;
#                  grub-common/grub-bios/grub-efi -> grub (monolithic)
#   profiles/server: php85-cli/php85-fpm/php85-opcache/php85-* extensions
#                    -> php85 (single package; extensions return when
#                    libcurl/oniguruma ports land)
#
# r14 installs every profile in files/profiles rather than a hand-kept list.
# r13 shipped saphira-chroot's --bind support and six new profiles and
# installed none of the profiles, because recipe_install enumerated them by
# name and nothing connected adding a profile to touching that list. An
# incomplete package reached the repository, which is exactly what the
# pkgrel discipline exists to prevent; r14 is the first revision whose
# payload actually matches its source.
depends="
	apk-tools
	coreutils
	saphira-base-abi
	util-linux
"
makedepends=""

recipe_build()
{
	local f
	sh -n "$RECIPE_DIR/files/saphira-install-plan" ||
		{ echo "ERROR: planner syntax check failed" >&2; return 1; }
	sh -n "$RECIPE_DIR/files/saphira-install-menu" ||
		{ echo "ERROR: menu syntax check failed" >&2; return 1; }
	sh -n "$RECIPE_DIR/files/saphira-image-creator-menu" ||
		{ echo "ERROR: creator menu syntax check failed" >&2; return 1; }
	sh "$RECIPE_DIR/tests/install-plan.sh" ||
		{ echo "ERROR: install-plan suite failed" >&2; return 1; }
	sh "$RECIPE_DIR/tests/install-menu.sh" ||
		{ echo "ERROR: install-menu suite failed" >&2; return 1; }
	sh "$RECIPE_DIR/tests/image-creator-appliance.sh" ||
		{ echo "ERROR: image-creator-appliance suite failed" >&2; return 1; }
	sh "$RECIPE_DIR/tests/genfstab.sh" ||
		{ echo "ERROR: genfstab suite failed" >&2; return 1; }
	sh "$RECIPE_DIR/tests/install-target-emptiness.sh" ||
		{ echo "ERROR: install-target-emptiness suite failed" >&2; return 1; }
	sh "$RECIPE_DIR/tests/bootstrap-target-emptiness.sh" ||
		{ echo "ERROR: bootstrap-target-emptiness suite failed" >&2; return 1; }
	for f in "$RECIPE_DIR"/files/saphira-* "$RECIPE_DIR"/files/profiles/*; do
		grep -q 'akadata-base-abi' "$f" && {
			echo "ERROR: unmigrated akadata-base-abi reference in $f" >&2
			return 1
		}
	done
	# Byte-pin the vendored payload.
	(cd "$RECIPE_DIR/files" && sha256sum -c files.sha256) || return 1
	# Profiles are DATA, and a data file that names a package which
	# does not exist produces an image that simply fails to install.
	# Every bare intention must be a real recipe, a -dev/-doc split
	# of one, a named split it declares, or a @-include resolving to
	# a profile in this tree (with the historical
	# @saphira-stage4-/@akadata-stage4- alias spelling).
	local pkg entry target base
	# Named splits (qemu-virgl, linux-firmware-i915, ...) have no
	# recipe directory of their own; resolve them through the
	# subpackages= declaration of their producer recipe.
	split_producers=$(for rd in $(grep -rl '^subpackages=' "$SAPHIRA_RECIPE_ROOT"/*/recipe.sh 2>/dev/null); do
		rp=${rd%/recipe.sh}; rp=${rp##*/}
		# Value may span lines; the opening line itself can also
		# close it (subpackages="..."). Strip the opener first so
		# the closing-quote test cannot fire on the same line.
		subs=$(awk 'BEGIN{flag=0} /^subpackages=/{sub(/^subpackages="/,""); flag=1} flag{buf=buf $0 "\n"; if (/"$/) exit} END{printf "%s", buf}' "$rd" | tr '\n' ' ' | sed -e 's/"//g')
		for s in $subs; do
			case $s in
			'$pkgname'*) s=$rp${s#'$pkgname'} ;;
			esac
			[ -n "$s" ] || continue
			printf '%s:%s\n' "$s" "$rp"
		done
	done)
	for f in "$RECIPE_DIR"/files/profiles/*; do
		case $f in *.services) continue ;; esac
		awk '
			{ line = $0; sub(/#.*$/, "", line) }
			line ~ /^[[:space:]]*$/ { next }
			{ gsub(/^[ \t]+|[ \t]+$/, "", line); print line }
		' "$f" | while read -r pkg; do
			[ -n "$pkg" ] || continue
			case $pkg in
			@*)	entry=${pkg#@}
				case $entry in
				saphira-stage4-*|akadata-stage4-*)
					target=${entry#saphira-stage4-}
					target=${target#akadata-stage4-} ;;
				*)	target=$entry ;;
				esac
				[ -f "$RECIPE_DIR/files/profiles/$target" ] || {
					echo "ERROR: ${f##*/} includes missing profile: $pkg" >&2
					exit 1
				} ;;
			*[![:alnum:]._+-]*) continue ;;
			*)	# -dev/-doc names resolve to the base recipe (repo
				# convention): ncurses-dev is proven by ncurses/.
				base=$pkg
				case $base in
				*-dev) base=${base%-dev} ;;
				*-doc) base=${base%-doc} ;;
				esac
				if [ -f "$SAPHIRA_RECIPE_ROOT/$base/recipe.sh" ]; then
					:
				elif printf '%s\n' "$split_producers" | grep -qF "$pkg:"; then
					# Named split (qemu-virgl, linux-firmware-i915):
					# proven by its producer recipe's subpackages=.
					:
				else
					echo "ERROR: ${f##*/} names $pkg, which has no recipe" >&2
					exit 1
				fi ;;
			esac
		done || return 1
	done
}

recipe_install()
{
	for tool in saphira-chroot saphira-bootstrap saphira-genfstab saphira-assemble-rootfs saphira-install saphira-install-plan saphira-install-menu; do
		install -D -m 0755 "$RECIPE_DIR/files/$tool" "$PKGDEST/usr/bin/$tool"
	done
	# Ram-mode installer entrypoint (runs inside the initramfs; see
	# installer-initramfs.conf for the composition contract).
	install -D -m 0755 "$RECIPE_DIR/files/installer-entrypoint" \
		"$PKGDEST/lib/saphira/installer-entrypoint"
	# Every profile is installed, not a hand-kept list. The list was the
	# defect: saphira-chroot's --bind support and six new profiles shipped in
	# a package that installed neither, because nothing about adding a
	# profile forced anyone to touch this loop. Two profiles added in one
	# sitting and both were silently absent from the published payload.
	# Enumerating the directory means a new profile cannot be forgotten.
	for profile in "$RECIPE_DIR"/files/profiles/*; do
		case $profile in
		*.services) continue ;;
		esac
		install -D -m 0644 "$profile" \
			"$PKGDEST/usr/share/saphira/profiles/$(basename "$profile")"
	done
	for sidecar in "$RECIPE_DIR"/files/profiles/*.services; do
		install -D -m 0644 "$sidecar" \
			"$PKGDEST/usr/share/saphira/profiles/$(basename "$sidecar")"
	done
	install -D -m 0644 "$RECIPE_DIR/files/saphira-bootstrap.8" \
		"$PKGDEST/usr/share/man/man8/saphira-bootstrap.8"
	install -D -m 0644 "$RECIPE_DIR/files/saphira-profiles.5" \
		"$PKGDEST/usr/share/man/man5/saphira-profiles.5"
	install -D -m 0644 "$RECIPE_DIR/files/saphira-assemble-rootfs.8" \
		"$PKGDEST/usr/share/man/man8/saphira-assemble-rootfs.8"
	install -D -m 0644 "$RECIPE_DIR/files/saphira-install.8" \
		"$PKGDEST/usr/share/man/man8/saphira-install.8"
	install -D -m 0644 "$RECIPE_DIR/files/saphira-install-plan.5" \
		"$PKGDEST/usr/share/man/man5/saphira-install-plan.5"
	install -D -m 0644 "$RECIPE_DIR/files/saphira-install-plan.8" \
		"$PKGDEST/usr/share/man/man8/saphira-install-plan.8"
	install -D -m 0644 "$RECIPE_DIR/files/saphira-install-menu.8" \
		"$PKGDEST/usr/share/man/man8/saphira-install-menu.8"
	install -D -m 0644 "$RECIPE_DIR/files/saphira-install-menu.service" \
		"$PKGDEST/usr/lib/systemd/system/saphira-install-menu.service"
	install -D -m 0755 "$RECIPE_DIR/files/saphira-image-creator-menu" \
		"$PKGDEST/usr/bin/saphira-image-creator-menu"
	install -D -m 0644 "$RECIPE_DIR/files/saphira-image-creator-menu.service" \
		"$PKGDEST/usr/lib/systemd/system/saphira-image-creator-menu.service"
	install -D -m 0644 "$RECIPE_DIR/files/saphira-image-creator-recovery.service" \
		"$PKGDEST/usr/lib/systemd/system/saphira-image-creator-recovery.service"
	install -D -m 0755 "$RECIPE_DIR/files/saphira-image-creator-menu.initd" \
		"$PKGDEST/etc/init.d/saphira-image-creator-menu"
	install -D -m 0644 "$RECIPE_DIR/files/saphira-image-creator-menu.8" \
		"$PKGDEST/usr/share/man/man8/saphira-image-creator-menu.8"
	install -D -m 0644 "$RECIPE_DIR/files/install-manifest.example" \
		"$PKGDEST/usr/share/saphira/install-manifest.example"
	install -D -m 0644 "$RECIPE_DIR/files/installer-initramfs.conf" \
		"$PKGDEST/usr/share/saphira/installer-initramfs.conf"
	install -D -m 0644 "$RECIPE_DIR/files/LICENSE" \
		"$PKGDEST/usr/share/licenses/saphira-install-tools/LICENSE"
}
