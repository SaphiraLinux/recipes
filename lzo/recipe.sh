#!/bin/sh

pkgname=lzo
pkgver=2.10
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Portable lossless data compression library"
license="GPL-2.0-or-later"
origin=lzo
repo=main
url=https://www.oberhumer.com/opensource/lzo/
source=https://deb.debian.org/debian/pool/main/l/lzo2/lzo2_2.10.orig.tar.gz
sha256=c0f892943208266f9b6543b3ae308fab6284c5c90e627931446fb49b4221a072

depends=""

makedepends="
    gawk
    
    gcc
    make
"

subpackages="
    $pkgname-dev
"

recipe_build()
{
	./configure \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--disable-static \
		--enable-shared
	make
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
}
