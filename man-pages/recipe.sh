#!/bin/sh
pkgname=man-pages
pkgver=6.15
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Linux man pages (sections 2, 3, 4, 5, 7)'
license='GPL-2.0-or-later Linux-man-pages-copyleft'
origin=man-pages
repo=saphira
url=https://www.kernel.org/doc/man-pages/
man_pages_sha256=03d8ebf618bd5df57cb4bf355efa3f4cd3a00b771efd623d4fd042b5dceb4465
depends=""
makedepends="make"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/man-pages-6.15.tar.xz"
	cd "$SRC"
	echo "$man_pages_sha256  $RECIPE_DIR/files/man-pages-6.15.tar.xz" | sha256sum -c -
}
recipe_install() {
	# man-pages GNUmakefile requires -R (no builtin variables).
	make -R -C "$SRC" install DESTDIR="$PKGDEST" prefix=/usr
}
