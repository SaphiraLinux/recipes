#!/bin/sh
pkgname=expat
pkgver=2.8.2
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='XML parser library'
license='MIT'
origin=expat
repo=saphira
url=https://libexpat.github.io/
expat_sha256=ef7d1994f533c9e7343d6c19f31064fc8ebbcbcaa144be3812b4f43052a05f4c
depends="gcc-libs"
# Stage4 generation shipped a separate libexpat package owning xmlwf and the
# shared objects. replaces is the apk-tools v3 ownership handover: files of
# the named packages may be taken over on upgrade without an overwrite
# error (solver ignores replaces; it is conflict metadata only).
replaces="libexpat"
makedepends="gawk gcc make pkgconf"
subpackages="$pkgname-dev $pkgname-doc"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/expat-2.8.2.tar.gz"
	cd "$SRC"
	echo "$expat_sha256  $RECIPE_DIR/files/expat-2.8.2.tar.gz" | sha256sum -c -
	./configure --prefix=/usr --disable-static 
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
