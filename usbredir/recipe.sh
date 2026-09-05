#!/bin/sh

pkgname=usbredir
pkgver=0.15.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='USB redirection protocol library and tools (SPICE USB passthrough)'
license='GPL-2.0-or-later AND LGPL-2.1-or-later'
origin=usbredir
repo=saphira
url=https://www.spice-space.org/usbredir.html
# Vendored: https://www.spice-space.org/download/usbredir/usbredir-0.15.0.tar.xz
usbredir_sha256=6dc2a380277688a068191245dac2ab7063a552999d8ac3ad8e841c10ff050961

depends="libusb glib"
makedepends="
	binutils
	gcc
	glib-dev
	libusb-dev
	meson
	ninja
	pkgconf
"

subpackages="$pkgname-dev"

recipe_build()
{
	URBALL="$RECIPE_DIR/files/usbredir-0.15.0.tar.xz"
	echo "$usbredir_sha256  $URBALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$URBALL"
	meson setup build "$SRC" \
		--prefix=/usr \
		-Dlibdir=lib \
		-Dtools=enabled
	meson compile -C build
}

recipe_install()
{
	DESTDIR="$PKGDEST" meson install -C build
}
