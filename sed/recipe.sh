#!/bin/sh
pkgname=sed
pkgver=4.9
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='GNU stream editor'
license='GPL-3.0-or-later'
origin=sed
repo=saphira
url=https://www.gnu.org/software/sed/
sed_sha256=6e226b732e1cd739464ad6862bd1a1aba42d7982922da7a53519631d24975181
depends=""
makedepends="gawk gcc make texinfo"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/sed-4.9.tar.xz"
	cd "$SRC"
	echo "$sed_sha256  $RECIPE_DIR/files/sed-4.9.tar.xz" | sha256sum -c -
	./configure --prefix=/usr --disable-nls
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
