#!/bin/sh
pkgname=groff
pkgver=1.23.0
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='GNU document formatting system (man page rendering)'
license='GPL-3.0-or-later'
origin=groff
repo=saphira
url=https://www.gnu.org/software/groff/
groff_sha256=6b9757f592b7518b4902eb6af7e54570bdccba37a871fddb2d30ae3863511c13
depends="gcc-libs"
makedepends="gawk gcc make perl texinfo m4 flex bison"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/groff-1.23.0.tar.gz"
	cd "$SRC"
	echo "$groff_sha256  $RECIPE_DIR/files/groff-1.23.0.tar.gz" | sha256sum -c -
	CFLAGS="${CFLAGS-} -std=gnu11" PAGE=A4 ./configure --prefix=/usr --without-x --without-libpng
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
	# gettext's charset.alias is a glibc-locale artifact; musl ignores it
	# and exactly one package may claim the path. Nothing ships it.
	rm -f "$PKGDEST/usr/lib/charset.alias"
}
