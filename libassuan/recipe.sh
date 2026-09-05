#!/bin/sh
pkgname=libassuan
pkgver=3.0.2
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='IPC library used by GnuPG'
license='LGPL-2.1-or-later GPL-3.0-or-later'
origin=libassuan
repo=saphira
url=https://www.gnupg.org/related_software/libassuan/
libassuan_sha256=d2931cdad266e633510f9970e1a2f346055e351bb19f9b78912475b8074c36f6
depends="libgpg-error"
makedepends="gawk gcc make pkgconf libgpg-error-dev"
subpackages="$pkgname-dev $pkgname-doc"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/libassuan-3.0.2.tar.bz2"
	cd "$SRC"
	echo "$libassuan_sha256  $RECIPE_DIR/files/libassuan-3.0.2.tar.bz2" | sha256sum -c -
	./configure --prefix=/usr --disable-static 
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
