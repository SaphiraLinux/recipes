#!/bin/sh
pkgname=oniguruma
pkgver=6.9.10
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Regular expressions library (ruby)'
license='BSD-2-Clause'
origin=oniguruma
repo=saphira
url=https://github.com/kkos/oniguruma
oniguruma_sha256=2a5cfc5ae259e4e97f86b68dfffc152cdaffe94e2060b770cb827238d769fc05
depends=""
makedepends="gawk gcc make"
subpackages="$pkgname-dev"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/onig-6.9.10.tar.gz"
	cd "$SRC"
	echo "$oniguruma_sha256  $RECIPE_DIR/files/onig-6.9.10.tar.gz" | sha256sum -c -
	./configure --prefix=/usr --libdir=/usr/lib --disable-static
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
	find "$PKGDEST" -name '*.la' -delete
}
