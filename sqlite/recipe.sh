#!/bin/sh
pkgname=sqlite
pkgver=3.53.3
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Self-contained, serverless, zero-configuration SQL database engine'
license='Public-Domain'
origin=sqlite
repo=saphira
url=https://www.sqlite.org/
sqlite_sha256=c917d7db16648ec95f714974ace5e5dcf46b7dc70e26600a0a102a3141125db0
depends="gcc-libs"
makedepends="gawk gcc make pkgconf readline-dev zlib-dev"
subpackages="$pkgname-dev $pkgname-doc"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/sqlite-autoconf-3530300.tar.gz"
	cd "$SRC"
	echo "$sqlite_sha256  $RECIPE_DIR/files/sqlite-autoconf-3530300.tar.gz" | sha256sum -c -
	./configure --prefix=/usr --disable-static \
		--enable-fts3 --enable-fts4 --enable-fts5 \
		--enable-rtree --enable-geopoly \
		LDFLAGS="${LDFLAGS-} -Wl,-soname,libsqlite3.so.0" \
		CFLAGS="${CFLAGS-} -DSQLITE_ENABLE_COLUMN_METADATA=1 \
			-DSQLITE_ENABLE_DBSTAT_VTAB=1 \
			-DSQLITE_ENABLE_MATH_FUNCTIONS=1 \
			-DSQLITE_ENABLE_UNLOCK_NOTIFY=1 \
			-DSQLITE_SECURE_DELETE=1 \
			-DSQLITE_THREADSAFE=1"
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
