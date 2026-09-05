#!/bin/sh
pkgname=gdbm
pkgver=1.26
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='GNU dbm key/value database library'
license='GPL-3.0-or-later'
origin=gdbm
repo=saphira
url=https://www.gnu.org/software/gdbm/
gdbm_sha256=6a24504a14de4a744103dcb936be976df6fbe88ccff26065e54c1c47946f4a5e
depends=""
makedepends="gawk gcc make"
subpackages="$pkgname-dev"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/gdbm-1.26.tar.gz"
	cd "$SRC"
	echo "$gdbm_sha256  $RECIPE_DIR/files/gdbm-1.26.tar.gz" | sha256sum -c -
	./configure --prefix=/usr --libdir=/usr/lib --disable-static --disable-nls --without-readline
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
	find "$PKGDEST" -name '*.la' -delete
}
