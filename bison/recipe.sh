#!/bin/sh

pkgname=bison
pkgver=3.8.2
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="General-purpose parser generator"
license="GPL-3.0-or-later"
origin=bison
repo=main
url=https://www.gnu.org/software/bison/
source=https://ftp.gnu.org/gnu/bison/bison-3.8.2.tar.xz
sha256=9bba0214ccf7f1079c5d59210045227bcf619519840ebfa80cd3849cff5a5bf2

depends="m4"

makedepends="
    binutils
    gawk
    gcc
    m4
    make
"

subpackages="bison-doc"
recipe_build()
{
	# Proven v0 flag --disable-yacc retained (no legacy yacc shim).
	./configure \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--disable-yacc
	make
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
}
