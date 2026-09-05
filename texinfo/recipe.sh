#!/bin/sh

pkgname=texinfo
pkgver=7.2
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="GNU documentation system for on-line and printed output"
license="GPL-3.0-or-later"
origin=texinfo
repo=main
url=https://www.gnu.org/software/texinfo/
source=https://ftp.gnu.org/gnu/texinfo/texinfo-7.2.tar.xz
sha256=0329d7788fbef113fa82cb80889ca197a344ce0df7646fe000974c5d714363a6

depends=""

makedepends="
    binutils
    gcc
    gawk
    make
    perl
"

subpackages="texinfo-doc"
recipe_build()
{
	# Proven v0 flags: no static libs, no perl XS extension.
	./configure \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--disable-static \
		--disable-perl-xs
	make
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
}
