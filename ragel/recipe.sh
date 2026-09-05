#!/bin/sh

pkgname=ragel
pkgver=6.10
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="State machine compiler that emits code for multiple languages"
license="MIT"
origin=ragel
repo=saphira
url=https://www.colm.net/open-source/ragel/
source=https://www.colm.net/files/ragel/ragel-6.10.tar.gz
sha256=5f156edb65d20b856d638dd9ee2dfb43285914d9aa2b6ec779dac0270cd56c3f

makedepends="
    binutils
    gcc
    make
"

recipe_build()
{
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	"$SRC/configure" --prefix=/usr --disable-manual
	make
}

recipe_install()
{
	make -C "$BUILDDIR" DESTDIR="$PKGDEST" install
}
