#!/bin/sh

pkgname=flex
pkgver=2.6.4
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Fast lexical analyser generator"
license="BSD-2-Clause"
origin=flex
repo=main
url=https://github.com/westes/flex
source=https://github.com/westes/flex/releases/download/v2.6.4/flex-2.6.4.tar.gz
sha256=e87aae032bf07c26f85ac0ed3250998c37621d95f8bd748b31f15b33c45ee995

depends="m4"

makedepends="
    binutils
    gawk
    gcc
    m4
    make
"

subpackages="flex-dev flex-doc"
recipe_build()
{
	# Proven v0 flags retained (--disable-bootstrap --enable-shared
	# --disable-static).
	./configure \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--disable-bootstrap \
		--enable-shared \
		--disable-static
	make
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
}
