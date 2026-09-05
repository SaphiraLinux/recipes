#!/bin/sh
pkgname=libmnl
pkgver=1.0.5
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Minimalistic Netlink communication library'
license='GPL-2.0-or-later'
origin=libmnl
repo=saphira
url=https://netfilter.org/projects/libmnl/
libmnl_sha256=274b9b919ef3152bfb3da3a13c950dd60d6e2bcd54230ffeca298d03b40d0525
depends=""
makedepends="gawk gcc make pkgconf"
subpackages="$pkgname-dev $pkgname-doc"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/libmnl-1.0.5.tar.bz2"
	cd "$SRC"
	echo "$libmnl_sha256  $RECIPE_DIR/files/libmnl-1.0.5.tar.bz2" | sha256sum -c -
	./configure --prefix=/usr --disable-static --disable-static
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
