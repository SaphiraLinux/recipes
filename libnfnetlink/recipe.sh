#!/bin/sh
pkgname=libnfnetlink
pkgver=1.0.2
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Low-level Netfilter netlink library'
license='GPL-2.0-or-later'
origin=libnfnetlink
repo=saphira
url=https://netfilter.org/projects/libnfnetlink/
libnfnetlink_sha256=b064c7c3d426efb4786e60a8e6859b82ee2f2c5e49ffeea640cfe4fe33cbc376
depends=""
makedepends="gawk gcc make pkgconf"
subpackages="$pkgname-dev $pkgname-doc"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/libnfnetlink-1.0.2.tar.bz2"
	cd "$SRC"
	echo "$libnfnetlink_sha256  $RECIPE_DIR/files/libnfnetlink-1.0.2.tar.bz2" | sha256sum -c -
	./configure --prefix=/usr --disable-static --disable-static
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
