#!/bin/sh
pkgname=libnetfilter_conntrack
pkgver=1.1.1
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Netfilter userspace conntrack library'
license='GPL-2.0-or-later'
origin=libnetfilter_conntrack
repo=saphira
url=https://netfilter.org/projects/libnetfilter_conntrack/
libnetfilter_conntrack_sha256=769d3eaf57fa4fbdb05dd12873b6cb9a5be7844d8937e222b647381d44284820
depends="libmnl libnfnetlink"
makedepends="gawk gcc make pkgconf libmnl-dev libnfnetlink-dev"
subpackages="$pkgname-dev"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/libnetfilter_conntrack-1.1.1.tar.xz"
	cd "$SRC"
	echo "$libnetfilter_conntrack_sha256  $RECIPE_DIR/files/libnetfilter_conntrack-1.1.1.tar.xz" | sha256sum -c -
	# kernel UAPI coordination is handled by header patches:
	# saphira-kernel-headers=7.1.5 0003-libc-compat-musl + musl 0002-netinet-in6
	./configure --prefix=/usr --disable-static 
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
