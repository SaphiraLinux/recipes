#!/bin/sh
pkgname=libnetfilter_cthelper
pkgver=1.0.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Netfilter conntrack helper library'
license='GPL-2.0-or-later'
origin=libnetfilter_cthelper
repo=saphira
url=https://netfilter.org/projects/libnetfilter_cthelper/
libnetfilter_cthelper_sha256=14073d5487233897355d3ff04ddc1c8d03cc5ba8d2356236aa88161a9f2dc912
depends="libmnl"
makedepends="gawk gcc make pkgconf libmnl-dev"
subpackages="$pkgname-dev"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/libnetfilter_cthelper-1.0.1.tar.bz2"
	cd "$SRC"
	echo "$libnetfilter_cthelper_sha256  $RECIPE_DIR/files/libnetfilter_cthelper-1.0.1.tar.bz2" | sha256sum -c -
	./configure --prefix=/usr --disable-static 
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
