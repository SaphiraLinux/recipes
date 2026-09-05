#!/bin/sh
pkgname=libnetfilter_queue
pkgver=1.0.5
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Userspace packet queueing Netfilter library'
license='GPL-2.0-or-later'
origin=libnetfilter_queue
repo=saphira
url=https://netfilter.org/projects/libnetfilter_queue/
libnetfilter_queue_sha256=f9ff3c11305d6e03d81405957bdc11aea18e0d315c3e3f48da53a24ba251b9f5
depends="libmnl libnfnetlink"
makedepends="gawk gcc make pkgconf libmnl-dev libnfnetlink-dev"
subpackages="$pkgname-dev"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/libnetfilter_queue-1.0.5.tar.bz2"
	cd "$SRC"
	echo "$libnetfilter_queue_sha256  $RECIPE_DIR/files/libnetfilter_queue-1.0.5.tar.bz2" | sha256sum -c -
	./configure --prefix=/usr --disable-static 
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
