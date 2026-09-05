#!/bin/sh

pkgname=isl
pkgver=0.27
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Integer set library for polyhedral analysis"
license="MIT"
origin=isl
repo=main
url=https://libisl.sourceforge.io/
source=https://libisl.sourceforge.io/isl-0.27.tar.xz
sha256=6d8babb59e7b672e8cb7870e874f3f7b813b6e00e6af3f8b04f7579965643d5c

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
		--with-gmp-prefix=/usr \
		--enable-shared \
		--enable-static
	make
}

recipe_install()
{
	cd "$BUILDDIR"
	make DESTDIR="$PKGDEST" install
}
