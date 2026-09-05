#!/bin/sh
pkgname=ipvsadm
pkgver=1.31
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Linux Virtual Server administration tool'
license='GPL-2.0-or-later'
origin=ipvsadm
repo=saphira
url=https://www.linuxvirtualserver.org/
ipvsadm_sha256=1a0a5e25b5a1226435d2fb76341656f83a710183aebb0d204db39c0ec3bedfdb
depends="popt libnl"
makedepends="popt-dev libnl-dev saphira-kernel-headers=7.1.5 gcc make pkgconf"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/ipvsadm-1.31.tar.xz"
	cd "$SRC"
	echo "$ipvsadm_sha256  $RECIPE_DIR/files/ipvsadm-1.31.tar.xz" | sha256sum -c -
	# serial make required: "all: libs ipvsadm" with unwired
	# libipvs.a prerequisites races under -j
	make
}
recipe_install() {
	make -C "$SRC" install BUILD_ROOT="$PKGDEST"
}
