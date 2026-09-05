#!/bin/sh
pkgname=dnsmasq
pkgver=2.93
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Lightweight DNS forwarder, DHCP and TFTP server'
license='GPL-2.0-or-later'
origin=dnsmasq
repo=saphira
url=https://thekelleys.org.uk/dnsmasq/doc.html
dnsmasq_sha256=0c00d4e5c97c8306e5fb932b348b34269c9c29a0e7df0e8e82958b407092bc19
depends=""
makedepends="saphira-kernel-headers=7.1.5 gcc make"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/dnsmasq-2.93.tar.xz"
	cd "$SRC"
	echo "$dnsmasq_sha256  $RECIPE_DIR/files/dnsmasq-2.93.tar.xz" | sha256sum -c -
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" install PREFIX=/usr DESTDIR="$PKGDEST"
}
