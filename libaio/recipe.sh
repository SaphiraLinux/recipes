#!/bin/sh
pkgname=libaio
pkgver=0.3.113
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Linux-native asynchronous I/O access library'
license='LGPL-2.1-or-later'
origin=libaio
repo=saphira
url=https://pagure.io/libaio
libaio_sha256=2c44d1c5fd0d43752287c9ae1eb9c023f04ef848ea8d4aafa46e9aedb678200b
depends=""
makedepends="gcc make"
subpackages="$pkgname-dev"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/libaio-0.3.113.tar.gz"
	cd "$SRC"
	echo "$libaio_sha256  $RECIPE_DIR/files/libaio-0.3.113.tar.gz" | sha256sum -c -
	make -j${JOBS:-$(nproc)} prefix=/usr libdir=/usr/lib
}
recipe_install() {
	make -C "$SRC" install prefix=/usr libdir=/usr/lib DESTDIR="$PKGDEST"
}
