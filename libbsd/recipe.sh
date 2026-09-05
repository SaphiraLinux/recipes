#!/bin/sh
pkgname=libbsd
pkgver=0.12.2
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='BSD compatibility library'
license='BSD-3-Clause AND MIT AND ISC'
origin=libbsd
repo=saphira
url=https://libbsd.freedesktop.org/
libbsd_sha256=b88cc9163d0c652aaf39a99991d974ddba1c3a9711db8f1b5838af2a14731014
depends="libmd"
makedepends="gawk gcc libmd-dev make"
subpackages="$pkgname-dev $pkgname-doc"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/libbsd-0.12.2.tar.xz"
	cd "$SRC"
	echo "$libbsd_sha256  $RECIPE_DIR/files/libbsd-0.12.2.tar.xz" | sha256sum -c -
	./configure --prefix=/usr --libdir=/usr/lib --disable-static
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
	find "$PKGDEST" -name '*.la' -delete
}
