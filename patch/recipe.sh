#!/bin/sh
pkgname=patch
pkgver=2.7.6
pkgrel=4
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='GNU patch utility'
license='GPL-3.0-or-later'
origin=patch
repo=saphira
url=https://www.gnu.org/software/patch/
patch_sha256=ac610bda97abe0d9f6b7c963255a11dcb196c25e337c61f94e4778d632f1d8fd
depends=""
makedepends="gawk gcc make"
subpackages="$pkgname-doc"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/patch-2.7.6.tar.xz"
	cd "$SRC"
	echo "$patch_sha256  $RECIPE_DIR/files/patch-2.7.6.tar.xz" | sha256sum -c -
	./configure --prefix=/usr --disable-xattr
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
	# gettext's charset.alias is a glibc-locale artifact; musl ignores it
	# and exactly one package may claim the path. Nothing ships it.
	rm -f "$PKGDEST/usr/lib/charset.alias"
}
