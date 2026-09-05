#!/bin/sh

pkgname=libpng
pkgver=1.6.50
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Portable Network Graphics (PNG) reference library"
license="Libpng"
origin=libpng
repo=saphira
url=http://www.libpng.org/pub/png/libpng.html
source=https://downloads.sourceforge.net/project/libpng/libpng16/1.6.50/libpng-1.6.50.tar.xz
sha256=4df396518620a7aa3651443e87d1b2862e4e88cad135a8b93423e01706232307

depends="
    zlib
"

makedepends="
    binutils
    gcc
    make
    pkgconf
    zlib-dev
"

# Development files ship in the main package; no -dev split.
recipe_build()
{
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	"$SRC/configure" --prefix=/usr --disable-static
	make
}

recipe_install()
{
	make -C "$BUILDDIR" DESTDIR="$PKGDEST" install
}
