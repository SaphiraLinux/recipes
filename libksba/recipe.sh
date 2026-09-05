#!/bin/sh
pkgname=libksba
pkgver=1.6.7
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='CMS and X.509 library used by GnuPG'
license='LGPL-3.0-or-later GPL-2.0-or-later'
origin=libksba
repo=saphira
url=https://www.gnupg.org/related_software/libksba/
libksba_sha256=cf72510b8ebb4eb6693eef765749d83677a03c79291a311040a5bfd79baab763
depends="libgpg-error"
makedepends="gawk gcc make pkgconf libgpg-error-dev"
subpackages="$pkgname-dev $pkgname-doc"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/libksba-1.6.7.tar.bz2"
	cd "$SRC"
	echo "$libksba_sha256  $RECIPE_DIR/files/libksba-1.6.7.tar.bz2" | sha256sum -c -
	./configure --prefix=/usr --disable-static 
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
