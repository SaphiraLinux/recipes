#!/bin/sh

pkgname=linux-firmware
pkgver=20260910
pkgrel=5
# r5: earlyfw refresh hooks honor the opt-in marker (generation only
# on opted machines; grub regen stays unconditional). Payload change.
# r4: earlyfw refresh hooks (payload change: hooks.d install/upgrade
# regenerates the per-kernel boot images from new blobs).
# r3: depless main, again (2026-10-23): the meta pin CANNOT live in
# this recipe. The seven splits auto-pin linux-firmware=$NVR, so a
# main that depends on them can never pass the INSTALL gate: pre-
# publication the repo holds the previous splits pinning the previous
# main, and apk refuses main-rN against splits-rN-1 as a version
# conflict (r3 proven). The full-set meta therefore lives OUTSIDE the
# pinned family as linux-firmware-full (separate recipe depending on
# the published splits - no circular pin, gate passes). Bare
# `apk add linux-firmware` installs WHENCE/licenses only; the
# usb-installer profile (unknown target hardware) uses -full.
# (No depends line: main is licence evidence only; see r3 note.)
# r2: family splits (2026-10-23): the 1.9G monolith becomes intel (377M
# iwlwifi/BT), i915 (28M Intel integrated + xe discrete GPU - the one
# non-network split most hosts need), amd (amdgpu/radeon/ucode),
# nvidia, qcom (524M SoC), network (all NICs/WLAN incl. Qualcomm ath*,
# mediatek, mellanox, netronome + root Wi-Fi blobs + the Chilli
# rt2870/mt7601u pair), misc (audio/video/USB-serial/SoC leftovers).
# Main keeps WHENCE/LICENSES/README (licence evidence) and depends on
# every split, so bare `apk add linux-firmware` behaves exactly as
# before while minimal hosts install only the families they need.
# Top-level dirs mapped 1:1 from the vendored tarball (stable upstream
# layout); explicit lists fail closed on typos. NOTA BENE: this
# snapshot ships NO intel-ucode (verified: zero matches in the
# tarball) - Intel microcode updates are a pre-existing upstream gap,
# unrelated to the split; amd-ucode rides in -amd.
subpackages="$pkgname-intel $pkgname-i915 $pkgname-amd $pkgname-nvidia $pkgname-qcom $pkgname-network $pkgname-misc"
# Sequencing note (kept for the record): r2 shipped main without the
# meta pin because resolvepkg satisfies depends only from published
# packages - the splits were brand-new then. r3 adds the pin now that
# all seven splits are published (same rule as qemu-virgl/libvirt).
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Linux firmware blobs for all in-kernel drivers (upstream snapshot)"
license="linux-firmware licence"
origin=linux-firmware
repo=saphira
url=https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git
source=https://www.kernel.org/pub/linux/kernel/firmware/linux-firmware-20260910.tar.xz
sha256=f3937ca282ba256242e2b6dbe523df8a80007d29ffd61f56d270190865492ea8

# Full upstream snapshot (657MB archive, ~1.8GB installed): every
# in-kernel driver finds its blob with no per-device selection to rot.
# Verified inside this snapshot before vendoring: rt2870.bin
# 251b8918... (Ralink RT5572) and mediatek/mt7601u.bin 4511b1d8...
# (MediaTek MT7601U) - the two Wi-Fi blobs proven on Hatched Chilli
# rigs. Upstream moved mt7601u.bin to mediatek/ but the driver still
# requests the bare name, so the recipe places a root copy beside the
# upstream path (plain copy, not a symlink: loader-proof and survives
# partial installs; extend the pattern if future moves break bare
# requests the same way).
# Install target is /lib/firmware (the kernel loader's hardcoded path
# on non-usrmerged Saphira - never /usr/lib/firmware). WHENCE +
# LICENSES/ ship as licence evidence. No daemon, no identities.

recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/linux-firmware-20260910.tar.xz" | sha256sum -c -
}

recipe_install()
{
	mkdir -p "$PKGDEST/lib/firmware"
	tar --no-same-owner -C "$PKGDEST/lib/firmware" --strip-components=1 \
		-xf "$RECIPE_DIR/files/linux-firmware-20260910.tar.xz"
	# Repo meta, not firmware: top-level dotfiles (.gitignore, CI bits)
	# and stray nested ones (ath11k .notice). No blob has a leading dot.
	find "$PKGDEST/lib/firmware" -name '.*' -mindepth 1 -exec rm -rf {} +
	# Upstream repo scaffolding (agent/CI/build files, not firmware or
	# licence evidence): WHENCE, LICENSE* and README stay.
	rm -f "$PKGDEST/lib/firmware/AGENTS.md" \
		"$PKGDEST/lib/firmware/Dockerfile" \
		"$PKGDEST/lib/firmware/Makefile"
	# The blobs the Chilli Wi-Fi rigs need must be present, including
	# the bare mt7601u.bin name the driver requests.
	cp "$PKGDEST/lib/firmware/mediatek/mt7601u.bin" \
		"$PKGDEST/lib/firmware/mt7601u.bin"
	[ -f "$PKGDEST/lib/firmware/rt2870.bin" ] ||
		{ printf 'linux-firmware: rt2870.bin missing\n' >&2; exit 1; }
	[ -f "$PKGDEST/lib/firmware/mt7601u.bin" ] ||
		{ printf 'linux-firmware: mt7601u.bin missing\n' >&2; exit 1; }
	[ -f "$PKGDEST/lib/firmware/mediatek/mt7601u.bin" ] ||
		{ printf 'linux-firmware: mediatek/mt7601u.bin missing\n' >&2; exit 1; }
	# Early-firmware refresh on install/upgrade (2026-10-23): blob
	# changes must reach the per-kernel boot images, never sit stale
	# in /lib/firmware while /boot carries the old set. Same hooks.d
	# mechanism and contract as the kernel packages.
	install -d -m 0755 "$PKGDEST/usr/share/saphira/hooks.d/$pkgname"
	install -m 0755 "$RECIPE_DIR/files/hooks-earlyfw" \
		"$PKGDEST/usr/share/saphira/hooks.d/$pkgname/post-install"
	install -m 0755 "$RECIPE_DIR/files/hooks-earlyfw" \
		"$PKGDEST/usr/share/saphira/hooks.d/$pkgname/post-upgrade"
}
