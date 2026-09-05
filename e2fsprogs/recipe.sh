#!/bin/sh
pkgname=e2fsprogs
pkgver=1.47.2
pkgrel=4
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Ext2/3/4 filesystem utilities'
license='GPL-2.0-or-later LGPL-2.0-or-later BSD-3-Clause MIT'
origin=e2fsprogs
repo=saphira
url=https://e2fsprogs.sourceforge.net/
e2fsprogs_sha256=08242e64ca0e8194d9c1caad49762b19209a06318199b63ce74ae4ef2d74e63c
depends="util-linux"
makedepends="util-linux-dev gawk gcc make pkgconf saphira-kernel-headers=7.1.5"
subpackages="$pkgname-dev $pkgname-doc"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/e2fsprogs-1.47.2.tar.xz"
	cd "$SRC"
	echo "$e2fsprogs_sha256  $RECIPE_DIR/files/e2fsprogs-1.47.2.tar.xz" | sha256sum -c -
	./configure --prefix=/usr --sysconfdir=/etc \
		--disable-libuuid --disable-libblkid --disable-libss \
		--disable-fsck --disable-uuidd --disable-static \
		--disable-e2initrd-helper
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
