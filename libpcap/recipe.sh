#!/bin/sh
pkgname=libpcap
pkgver=1.10.6
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Packet capture library (tcpdump)'
license='BSD-3-Clause'
origin=libpcap
repo=saphira
url=https://www.tcpdump.org/
libpcap_sha256=872dd11337fe1ab02ad9d4fee047c9da244d695c6ddf34e2ebb733efd4ed8aa9
depends=""
makedepends="gawk gcc make pkgconf flex bison"
subpackages="$pkgname-dev $pkgname-doc"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/libpcap-1.10.6.tar.gz"
	cd "$SRC"
	echo "$libpcap_sha256  $RECIPE_DIR/files/libpcap-1.10.6.tar.gz" | sha256sum -c -
	./configure --prefix=/usr --disable-static --disable-dbus --without-libnl --disable-rdma
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
