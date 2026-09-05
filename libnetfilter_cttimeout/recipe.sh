#!/bin/sh
pkgname=libnetfilter_cttimeout
pkgver=1.0.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Netfilter conntrack timeout library'
license='GPL-2.0-or-later'
origin=libnetfilter_cttimeout
repo=saphira
url=https://netfilter.org/projects/libnetfilter_cttimeout/
libnetfilter_cttimeout_sha256=0b59da2f3204e1c80cb85d1f6d72285fc07b01a2f5678abf5dccfbbefd650325
depends="libmnl"
makedepends="gawk gcc make pkgconf libmnl-dev"
subpackages="$pkgname-dev"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/libnetfilter_cttimeout-1.0.1.tar.bz2"
	cd "$SRC"
	echo "$libnetfilter_cttimeout_sha256  $RECIPE_DIR/files/libnetfilter_cttimeout-1.0.1.tar.bz2" | sha256sum -c -
	./configure --prefix=/usr --disable-static 
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
