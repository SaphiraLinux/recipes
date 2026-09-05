#!/bin/sh
pkgname=iproute2
pkgver=7.1.0
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='IP routing utilities (ip, ss, tc, bridge)'
license='GPL-2.0-or-later'
origin=iproute2
repo=saphira
url=https://wiki.linuxfoundation.org/networking/iproute2
iproute2_sha256=fd9fa1b95809417157ca83dd72957e3261bdbce896353cb936f80af0b33a4b5c
depends="libmnl"
makedepends="saphira-kernel-headers=7.1.5 bison flex gawk gcc make pkgconf libmnl-dev"
subpackages="$pkgname-doc"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/iproute2-7.1.0.tar.xz"
	cd "$SRC"
	echo "$iproute2_sha256  $RECIPE_DIR/files/iproute2-7.1.0.tar.xz" | sha256sum -c -
	./configure --libbpf-force=off
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
