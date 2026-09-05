#!/bin/sh
pkgname=liburcu
pkgver=0.15.1
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Userspace RCU (read-copy-update) synchronization library'
license='LGPL-2.1-or-later MIT'
origin=liburcu
repo=saphira
url=https://liburcu.org/
liburcu_sha256=98d66cc12f2c5881879b976f0c55d10d311401513be254e3bd28cf3811fb50c8
depends="gcc-libs"
makedepends="gawk gcc make pkgconf"
subpackages="$pkgname-dev $pkgname-doc"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/userspace-rcu-0.15.1.tar.bz2"
	cd "$SRC"
	echo "$liburcu_sha256  $RECIPE_DIR/files/userspace-rcu-0.15.1.tar.bz2" | sha256sum -c -
	./configure --prefix=/usr --disable-static --disable-werror
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
