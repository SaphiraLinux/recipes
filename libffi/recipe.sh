#!/bin/sh
pkgname=libffi
pkgver=3.5.2
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Foreign function interface library'
license='MIT'
origin=libffi
repo=saphira
url=https://sourceware.org/libffi/
libffi_sha256=f3a3082a23b37c293a4fcd1053147b371f2ff91fa7ea1b2a52e335676bac82dc
depends=""
makedepends="gawk gcc make texinfo"
subpackages="$pkgname-dev $pkgname-doc"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/libffi-3.5.2.tar.gz"
	cd "$SRC"
	echo "$libffi_sha256  $RECIPE_DIR/files/libffi-3.5.2.tar.gz" | sha256sum -c -
	./configure --prefix=/usr --libdir=/usr/lib --disable-static
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
	find "$PKGDEST" -name '*.la' -delete
}
