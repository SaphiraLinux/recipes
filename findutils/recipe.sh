#!/bin/sh
pkgname=findutils
pkgver=4.10.0
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='GNU find, xargs and locate'
license='GPL-3.0-or-later'
origin=findutils
repo=saphira
url=https://www.gnu.org/software/findutils/
findutils_sha256=1387e0b67ff247d2abde998f90dfbf70c1491391a59ddfecb8ae698789f0a4f5
depends=""
makedepends="gawk gcc make"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/findutils-4.10.0.tar.xz"
	cd "$SRC"
	echo "$findutils_sha256  $RECIPE_DIR/files/findutils-4.10.0.tar.xz" | sha256sum -c -
	./configure --prefix=/usr --disable-nls --localstatedir=/var/lib/locate
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
