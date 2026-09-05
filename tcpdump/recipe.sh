#!/bin/sh
pkgname=tcpdump
pkgver=4.99.6
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Powerful command-line packet analyzer'
license='BSD-3-Clause'
origin=tcpdump
repo=saphira
url=https://www.tcpdump.org/
tcpdump_sha256=5839921a0f67d7d8fa3dacd9cd41e44c89ccb867e8a6db216d62628c7fd14b09
depends="libpcap openssl"
makedepends="gawk gcc make pkgconf libpcap-dev openssl-dev"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/tcpdump-4.99.6.tar.gz"
	cd "$SRC"
	echo "$tcpdump_sha256  $RECIPE_DIR/files/tcpdump-4.99.6.tar.gz" | sha256sum -c -
	./configure --prefix=/usr --without-smi
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
