#!/bin/sh
pkgname=dbus
pkgver=1.16.0
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='D-Bus message bus system'
license='GPL-2.0-or-later AFL-2.1'
origin=dbus
repo=saphira
url=https://www.freedesktop.org/wiki/Software/dbus/
dbus_sha256=9f8ca5eb51cbe09951aec8624b86c292990ae2428b41b856e2bed17ec65c8849
depends="expat systemd"
makedepends="meson ninja expat-dev gcc pkgconf saphira-kernel-headers=7.1.5 systemd"
subpackages="$pkgname-dev $pkgname-doc"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/dbus-1.16.0.tar.xz"
	cd "$SRC"
	echo "$dbus_sha256  $RECIPE_DIR/files/dbus-1.16.0.tar.xz" | sha256sum -c -
	meson setup _build --prefix=/usr \
		-Dsystemd=enabled -Dsystemd_system_unitdir=/usr/lib/systemd/system \
		-Dx11_autolaunch=disabled -Dxml_docs=disabled \
		-Dmodular_tests=disabled \
		-Dsysconfdir=/etc -Dlocalstatedir=/var
	meson compile -C _build
}
recipe_install() {
	DESTDIR="$PKGDEST" meson install -C "$SRC/_build"
	# Dual-init policy: the systemd bus unit ships via meson; the OpenRC
	# counterpart ships from files/ - neither wraps the other, neither
	# is auto-enabled.
	install -D -m 0755 "$RECIPE_DIR/files/dbus.initd" \
		"$PKGDEST/etc/init.d/dbus"
}
