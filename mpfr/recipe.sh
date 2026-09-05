#!/bin/sh

pkgname=mpfr
pkgver=4.2.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Multiple-precision floating-point computations library"
license="LGPL-3.0-or-later"
origin=mpfr
repo=main
url=https://www.mpfr.org/
source=https://www.mpfr.org/mpfr-4.2.2/mpfr-4.2.2.tar.xz
sha256=b67ba0383ef7e8a8563734e2e889ef5ec3c3b898a01d00fa0a6869ad81c6ce01

depends="
    gmp
"

makedepends="
    binutils
    gawk
    gcc
    make
    gmp-dev
"

subpackages="
    $pkgname-dev
"

recipe_build()
{
	# Out-of-tree build per the proven v0 recipe.
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	"$SRC/configure" \
		--prefix=/usr \
		--libdir=/usr/lib \
		--with-gmp=/usr \
		--enable-shared \
		--enable-static
	make
}

recipe_install()
{
	cd "$BUILDDIR"
	make DESTDIR="$PKGDEST" install
}
