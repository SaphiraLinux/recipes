#!/bin/sh

pkgname=pixman
pkgver=0.46.4
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='The pixel-manipulation library for X and cairo'
license='MIT'
origin=pixman
repo=saphira
url=https://www.cairographics.org/
# Vendored: https://www.cairographics.org/releases/pixman-0.46.4.tar.xz
pixman_sha256=a098c33924754ad43f981b740f6d576c70f9ed1006e12221b1845431ebce1239

depends=""
makedepends="
	binutils
	gcc
	meson
	ninja
	pkgconf
"

subpackages="$pkgname-dev"

recipe_build()
{
	PXBALL="$RECIPE_DIR/files/pixman-0.46.4.tar.xz"
	echo "$pixman_sha256  $PXBALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$PXBALL"
	meson setup build "$SRC" \
		--prefix=/usr \
		-Dlibdir=lib \
		-Dgtk=disabled \
		-Dtests=disabled \
		-Ddemos=disabled \
		-Dlibpng=disabled
	meson compile -C build
}

recipe_install()
{
	DESTDIR="$PKGDEST" meson install -C build
}
