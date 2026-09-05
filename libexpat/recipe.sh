#!/bin/sh

pkgname=libexpat
pkgver=2.8.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Expat XML parser library"
license="MIT"
origin=libexpat
repo=saphira
url=https://libexpat.github.io/
source=https://github.com/libexpat/libexpat/releases/download/R_2_8_2/expat-2.8.2.tar.gz
sha256=ef7d1994f533c9e7343d6c19f31064fc8ebbcbcaa144be3812b4f43052a05f4c
# Superseded: the expat recipe is canonical (it declares replaces=libexpat,
# the apk-tools v3 ownership handover). Kept for provenance only; resolvepkg
# skips it and nothing may depend on it.
disabled=yes
disabled_reason='superseded by the expat recipe (replaces=libexpat handover); both in one index collides on the sonames'

makedepends="
    binutils
    gcc
    make
"

# Historical state kept verbatim below (this recipe is disabled).
recipe_build()
{
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	"$SRC/configure" --prefix=/usr \
		--without-examples --without-tests --without-docbook \
		--disable-static
	make
}

recipe_install()
{
	make -C "$BUILDDIR" DESTDIR="$PKGDEST" install
}
