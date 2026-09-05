#!/bin/sh
pkgname=which
pkgver=2.25
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Shows the full path of (shell) commands'
license='GPL-3.0-or-later'
origin=which
repo=saphira
url=https://www.gnu.org/software/which/
which_sha256=1cb83e4f702e60b8211ab5ec4c2afbab1b1dec80209456a7d2faf7584ed225ea
depends=""
makedepends="gcc make"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/which-2.25.tar.gz"
	cd "$SRC"
	echo "$which_sha256  $RECIPE_DIR/files/which-2.25.tar.gz" | sha256sum -c -
	CFLAGS="${CFLAGS-} -std=gnu11" ./configure --prefix=/usr --disable-static
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
