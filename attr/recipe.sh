#!/bin/sh
pkgname=attr
pkgver=2.5.2
pkgrel=6
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Utilities for manipulating filesystem extended attributes'
license='GPL-2.0-or-later AND LGPL-2.1-or-later'
origin=attr
repo=saphira
url=https://savannah.nongnu.org/projects/attr/
attr_sha256=f2e97b0ab7ce293681ab701915766190d607a1dba7fae8a718138150b700a70b
depends=""
makedepends="gawk gcc make"
subpackages="$pkgname-dev attr-doc"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/attr-2.5.2.tar.xz"
	cd "$SRC"
	echo "$attr_sha256  $RECIPE_DIR/files/attr-2.5.2.tar.xz" | sha256sum -c -
	CFLAGS="-D_GNU_SOURCE -include libgen.h ${CFLAGS:--O2}" ./configure --prefix=/usr --sysconfdir=/etc --libdir=/usr/lib --disable-nls
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
	find "$PKGDEST" -name '*.la' -delete
}
