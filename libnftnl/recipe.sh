#!/bin/sh
pkgname=libnftnl
pkgver=1.3.1
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Netfilter nftables userspace library'
license='GPL-2.0-or-later'
origin=libnftnl
repo=saphira
url=https://netfilter.org/projects/libnftnl/
libnftnl_sha256=607da28dba66fbdeccf8ef1395dded9077e8d19f2995f9a4d45a9c2f0bcffba8
depends="libmnl"
makedepends="gawk gcc make pkgconf libmnl-dev"
subpackages="$pkgname-dev $pkgname-doc"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/libnftnl-1.3.1.tar.xz"
	cd "$SRC"
	echo "$libnftnl_sha256  $RECIPE_DIR/files/libnftnl-1.3.1.tar.xz" | sha256sum -c -
	./configure --prefix=/usr --disable-static 
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
