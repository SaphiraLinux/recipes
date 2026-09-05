#!/bin/sh
pkgname=npth
pkgver=1.8
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='New GNU portable threads library'
license='LGPL-2.1-or-later'
origin=npth
repo=saphira
url=https://www.gnupg.org/related_software/npth/
npth_sha256=8bd24b4f23a3065d6e5b26e98aba9ce783ea4fd781069c1b35d149694e90ca3e
depends=""
makedepends="gawk gcc make pkgconf"
subpackages="$pkgname-dev"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/npth-1.8.tar.bz2"
	cd "$SRC"
	echo "$npth_sha256  $RECIPE_DIR/files/npth-1.8.tar.bz2" | sha256sum -c -
	./configure --prefix=/usr --disable-static 
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
