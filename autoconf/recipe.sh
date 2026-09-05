#!/bin/sh
pkgname=autoconf
pkgver=2.73
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='GNU automatic configure script builder'
license='GPL-3.0-or-later'
origin=autoconf
repo=saphira
url=https://www.gnu.org/software/autoconf/
autoconf_sha256=9fd672b1c8425fac2fa67fa0477b990987268b90ff36d5f016dae57be0d6b52e
depends="m4 perl"
makedepends="gawk make perl"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/autoconf-2.73.tar.xz"
	cd "$SRC"
	echo "$autoconf_sha256  $RECIPE_DIR/files/autoconf-2.73.tar.xz" | sha256sum -c -
	./configure --prefix=/usr
	make
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
