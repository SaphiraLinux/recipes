#!/bin/sh

pkgname=mpc
pkgver=1.3.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Multiple-precision complex arithmetic library"
license="LGPL-3.0-or-later"
origin=mpc
repo=main
url=https://www.multiprecision.org/mpc/
source=https://ftp.gnu.org/gnu/mpc/mpc-1.3.1.tar.gz
sha256=ab642492f5cf882b74aa0cb730cd410a81edcdbec895183ce930e706c1c759b8

depends="
    gmp
    mpfr
"

makedepends="
    binutils
    gawk
    gcc
    make
    gmp-dev
    mpfr-dev
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
		--with-mpfr=/usr \
		--enable-shared \
		--enable-static
	make
}

recipe_install()
{
	cd "$BUILDDIR"
	make DESTDIR="$PKGDEST" install
}
