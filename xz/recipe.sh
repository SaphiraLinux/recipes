#!/bin/sh
pkgname=xz
pkgver=5.8.3
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='XZ compression library and tools'
license='0BSD AND GPL-2.0-or-later AND LGPL-2.1-or-later'
origin=xz
repo=saphira
url=https://tukaani.org/xz/
xz_sha256=fff1ffcf2b0da84d308a14de513a1aa23d4e9aa3464d17e64b9714bfdd0bbfb6
depends=""
makedepends="gawk gcc make"
subpackages="$pkgname-dev"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/xz-5.8.3.tar.xz"
	cd "$SRC"
	echo "$xz_sha256  $RECIPE_DIR/files/xz-5.8.3.tar.xz" | sha256sum -c -
	./configure --prefix=/usr --disable-scripts --disable-nls
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
	find "$PKGDEST" -name '*.la' -delete
}
