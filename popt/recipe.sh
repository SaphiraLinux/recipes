#!/bin/sh
pkgname=popt
pkgver=1.19
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Command line option parsing library'
license='MIT'
origin=popt
repo=saphira
url=https://github.com/rpm-software-management/popt
popt_sha256=6eb40d650526cb9fe63eb4415bcecdf9cf306f7556e77eff689abc5a44670060
depends=""
makedepends="autoconf automake gawk gcc gettext libtool make"
subpackages="$pkgname-dev"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/popt-1.19.tar.gz"
	cd "$SRC"
	echo "$popt_sha256  $RECIPE_DIR/files/popt-1.19.tar.gz" | sha256sum -c -
	autoreconf -i
	./configure --prefix=/usr --libdir=/usr/lib --disable-static --disable-nls
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
	find "$PKGDEST" -name '*.la' -delete
}
