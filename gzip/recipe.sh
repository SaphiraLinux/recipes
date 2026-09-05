#!/bin/sh
pkgname=gzip
pkgver=1.13
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='GNU compression utility'
license='GPL-3.0-or-later'
origin=gzip
repo=saphira
url=https://www.gnu.org/software/gzip/
gzip_sha256=7454eb6935db17c6655576c2e1b0fabefd38b4d0936e0f87f48cd062ce91a057
depends=""
makedepends="gawk gcc make"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/gzip-1.13.tar.xz"
	cd "$SRC"
	echo "$gzip_sha256  $RECIPE_DIR/files/gzip-1.13.tar.xz" | sha256sum -c -
	./configure --prefix=/usr --disable-gcc-warnings
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
