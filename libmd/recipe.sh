#!/bin/sh
pkgname=libmd
pkgver=1.1.0
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Message digest functions from BSD systems'
license='BSD-3-Clause AND ISC AND MIT'
origin=libmd
repo=saphira
url=https://git.hadrons.org/git/libmd.git
libmd_sha256=1bd6aa42275313af3141c7cf2e5b964e8b1fd488025caf2f971f43b00776b332
depends=""
makedepends="gawk gcc make"
subpackages="$pkgname-dev"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/libmd-1.1.0.tar.xz"
	cd "$SRC"
	echo "$libmd_sha256  $RECIPE_DIR/files/libmd-1.1.0.tar.xz" | sha256sum -c -
	./configure --prefix=/usr --libdir=/usr/lib --disable-static
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
	find "$PKGDEST" -name '*.la' -delete
}
