#!/bin/sh
pkgname=man-db
pkgver=2.13.0
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Database-driven manual pager suite (man, apropos, whatis)'
license='GPL-2.0-or-later LGPL-2.1-or-later'
origin=man-db
repo=saphira
url=https://www.nongnu.org/man-db/
man_db_sha256=82f0739f4f61aab5eb937d234de3b014e777b5538a28cbd31433c45ae09aefb9
depends="libpipeline gdbm zlib groff"
makedepends="libpipeline-dev gdbm-dev zlib-dev gettext gcc make pkgconf"
subpackages="$pkgname-doc"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/man-db-2.13.0.tar.xz"
	cd "$SRC"
	echo "$man_db_sha256  $RECIPE_DIR/files/man-db-2.13.0.tar.xz" | sha256sum -c -
	./configure --prefix=/usr --sysconfdir=/etc \
		--disable-nls --disable-static \
		--with-db=gdbm --with-pager=less \
		--disable-setuid --enable-automatic-create
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
