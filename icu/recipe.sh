#!/bin/sh
pkgname=icu
pkgver=78.3
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='International Components for Unicode (C/C++ libraries)'
license='ICU'
origin=icu
repo=saphira
url=https://icu.unicode.org/
icu_sha256=3a2e7a47604ba702f345878308e6fefeca612ee895cf4a5f222e7955fabfe0c0
depends="gcc-libs"
makedepends="gawk gcc make python3"
subpackages="$pkgname-dev $pkgname-doc"
recipe_build() {
	tar --no-same-owner -C "$SRC" -xf "$RECIPE_DIR/files/icu4c-78.3-src.tgz"
	cd "$SRC/icu/source"
	echo "$icu_sha256  $RECIPE_DIR/files/icu4c-78.3-src.tgz" | sha256sum -c -
	./configure --prefix=/usr --libdir=/usr/lib \
		--disable-tests --disable-samples --disable-extras \
		--with-data-packaging=library
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC/icu/source" DESTDIR="$PKGDEST" install
}
