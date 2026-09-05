#!/bin/sh
pkgname=diffutils
pkgver=3.12
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='GNU diff utilities'
license='GPL-3.0-or-later'
origin=diffutils
repo=saphira
url=https://www.gnu.org/software/diffutils/
diffutils_sha256=7c8b7f9fc8609141fdea9cece85249d308624391ff61dedaf528fcb337727dfd
depends=""
makedepends="gawk gcc make"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/diffutils-3.12.tar.xz"
	cd "$SRC"
	echo "$diffutils_sha256  $RECIPE_DIR/files/diffutils-3.12.tar.xz" | sha256sum -c -
	./configure --prefix=/usr --disable-nls
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
