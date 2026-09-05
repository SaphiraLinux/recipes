#!/bin/sh
pkgname=ethtool
pkgver=7.1
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Network driver and hardware settings tool'
license='GPL-2.0-only'
origin=ethtool
repo=saphira
url=https://www.kernel.org/pub/software/network/ethtool/
ethtool_sha256=4d78c26edc0255bc92f4b995b5fd66108d75ff966ed4694f6025a6d370bc2496
depends="libmnl"
makedepends="saphira-kernel-headers=7.1.5 gawk gcc make pkgconf libmnl-dev"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/ethtool-7.1.tar.xz"
	cd "$SRC"
	echo "$ethtool_sha256  $RECIPE_DIR/files/ethtool-7.1.tar.xz" | sha256sum -c -
	./configure --prefix=/usr --disable-static --disable-netlink
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
