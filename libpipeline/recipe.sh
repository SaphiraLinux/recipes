#!/bin/sh
pkgname=libpipeline
pkgver=1.5.8
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Pipeline manipulation library (man-db dependency)'
license='GPL-3.0-or-later'
origin=libpipeline
repo=saphira
url=https://www.nongnu.org/libpipeline/
libpipeline_sha256=1b1203ca152ccd63983c3f2112f7fe6fa5afd453218ede5153d1b31e11bb8405
depends=""
makedepends="gawk gcc make pkgconf"
subpackages="$pkgname-dev"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/libpipeline-1.5.8.tar.gz"
	cd "$SRC"
	echo "$libpipeline_sha256  $RECIPE_DIR/files/libpipeline-1.5.8.tar.gz" | sha256sum -c -
	./configure --prefix=/usr --libdir=/usr/lib --disable-static
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
	find "$PKGDEST" -name '*.la' -delete
}
