#!/bin/sh

pkgname=linux-firmware
pkgver=20260910
pkgrel=1
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
}
