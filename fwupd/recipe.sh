#!/bin/sh
pkgname=fwupd
pkgver=2.1.8
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Firmware update daemon and tools (safe operations only in tests)'
license='LGPL-2.1-or-later'
origin=fwupd
repo=saphira
url=https://fwupd.org/
source=https://github.com/fwupd/fwupd/releases/download/2.1.8/fwupd-2.1.8.tar.xz
sha256=8724305a52621ab6586de3290f6a78edb8393a4aa4bcb6c63f9228ae5e00acf8

# Daemon package, dual-init: upstream systemd units ship (unit dir
# pinned below), OpenRC fwupd.initd added here, never auto-enabled.
# polkit=enabled is load-bearing: without polkit the daemon allows ALL
# client actions (upstream warning). gnutls preferred over openssl per
# upstream order. systemd_unit_user empty -> DynamicUser (no static
# refresh identity to own). supported_build stays auto (no .git in the
# tarball -> off, documented not silent). efi_binary off: fwupd-efi
# package provides the capsule binaries. plugin_uefi_capsule_splash
# off: boot-logo cosmetics needing python cairo/gi; cairo is forbidden
# by the headless policy, and capsule mechanics are unaffected.
# Explicitly disabled with reasons: bluez (absent, server-irrelevant),
# libdrm (headless policy: no libdrm), libmnl (absent), passim
# (absent P2P daemon), modem_manager (ModemManager absent),
# introspection (no consumers), docs (needs gi-docgen stack),
# umockdev_tests (umockdev absent; unit tests off too).
depends="glib libxmlb polkit sqlite"
# efivar + fwupd-efi (uefi-capsule plugin), libcurl (LVFS), blkid
# via util-linux (blkid.pc), readline for fwupdmgr, udev for hwdb and
# rules, json-glib for metadata, systemd-libs for logind and unit
# paths, jinja2 (hard meson requirement for man generation). gcab is
# folded in-tree upstream, so no libarchive involvement.
makedepends="binutils cmake curl-dev efivar-dev fwupd-efi gcc glib-dev gnutls-dev json-glib-dev libtasn1-dev libusb-dev libxmlb-dev make meson ncurses-dev nettle-dev ninja pcre2-dev libffi-dev pkgconf polkit-dev python3 python-jinja2 readline-dev sqlite-dev systemd-dev udev-dev util-linux-dev xz-dev zlib-dev zstd-dev"
subpackages="$pkgname-dev"

recipe_build() {
	FWUPD_BALL="$RECIPE_DIR/files/fwupd-${pkgver}.tar.xz"
	echo "$sha256  $FWUPD_BALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$FWUPD_BALL"
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	meson setup "$SRC" \
		--prefix=/usr \
		--libdir=lib \
		--sysconfdir=/etc \
		--buildtype=release \
		-Dbuild=all \
		-Dpolkit=enabled \
		-Dgnutls=enabled \
		-Dopenssl=disabled \
		-Dsystemd=enabled \
		-Dlogind=enabled \
		-Dintrospection=disabled \
		-Ddocs=disabled \
		-Dtests=false \
		-Dumockdev_tests=disabled \
		-Dbluez=disabled \
		-Dlibdrm=disabled \
		-Dlibmnl=disabled \
		-Dpassim=disabled \
		-Dplugin_modem_manager=disabled \
		-Dreadline=enabled \
		-Dhsi=enabled \
		-Dlvfs=true \
		-Dman=true \
		-Dmetainfo=true \
		-Dbash_completion=true \
		-Dfish_completion=true \
		-Dfirmware-packager=true \
		-Defi_binary=false \
		-Dplugin_uefi_capsule_splash=false \
		-Dudev_hotplug=true \
		-Dp2p_policy=metadata \
		-Dvendor_ids_dir=/usr/share/hwdata \
		-Dvalgrind=disabled
	meson compile
}

recipe_install() {
	DESTDIR="$PKGDEST" meson install -C "$BUILDDIR"
	# Units must live in /usr/lib/systemd/system regardless of what
	# systemd.pc resolves to in the build root.
	if [ -d "$PKGDEST/lib/systemd/system" ]; then
		mkdir -p "$PKGDEST/usr/lib/systemd/system"
		mv "$PKGDEST"/lib/systemd/system/*.service \
			"$PKGDEST/usr/lib/systemd/system/"
		rmdir "$PKGDEST/lib/systemd/system" 2>/dev/null || true
	fi
	# Upstream hardcodes /usr/lib/udev/rules.d; Saphira keeps rules in
	# /lib/udev (fuse3/libjaylink precedent).
	if [ -d "$PKGDEST/usr/lib/udev/rules.d" ]; then
		mkdir -p "$PKGDEST/lib/udev"
		mv "$PKGDEST/usr/lib/udev/rules.d" "$PKGDEST/lib/udev/rules.d"
	fi
	# OpenRC half of dual-init (never auto-enabled).
	install -D -m 0755 "$RECIPE_DIR/files/fwupd.initd" \
		"$PKGDEST/etc/init.d/fwupd"
	find "$PKGDEST" -name '*.a' -delete
}
