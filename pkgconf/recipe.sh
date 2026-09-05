#!/bin/sh

pkgname=pkgconf
pkgver=2.4.3
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Package compiler and linker metadata toolkit"
license="ISC"
origin=pkgconf
repo=main
url=https://pkgconf.org/
source=https://distfiles.ariadne.space/pkgconf/pkgconf-${pkgver}.tar.xz
sha256=51203d99ed573fa7344bf07ca626f10c7cc094e0846ac4aa0023bd0c83c25a41

depends=""

makedepends="
    binutils
    gcc
    gawk
    make
"

recipe_build()
{
	./configure \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--disable-static
	make
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
	# Build systems look for the historical pkg-config program name; the
	# repository packaging previously shipped only pkgconf itself.
	ln -s pkgconf "$PKGDEST/usr/bin/pkg-config"
}
