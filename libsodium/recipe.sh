#!/bin/sh
pkgname=libsodium
pkgver=1.0.20
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Modern, portable, easy to use crypto library'
license='ISC'
origin=libsodium
repo=saphira
url=https://libsodium.gitbook.io/
libsodium_sha256=ebb65ef6ca439333c2bb41a0c1990587288da07f6c7fd07cb3a18cc18d30ce19
depends="gcc-libs"
makedepends="gawk gcc make pkgconf"
subpackages="$pkgname-dev"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/libsodium-1.0.20.tar.gz"
	cd "$SRC"
	echo "$libsodium_sha256  $RECIPE_DIR/files/libsodium-1.0.20.tar.gz" | sha256sum -c -
	./configure --prefix=/usr --disable-static 
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
