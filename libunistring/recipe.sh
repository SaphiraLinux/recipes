#!/bin/sh

pkgname=libunistring
pkgver=1.3
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="GNU Unicode string library"
license="LGPL-3.0-or-later GPL-2.0-or-later"
origin=libunistring
repo=main
url=https://www.gnu.org/software/libunistring/
subpackages="
    $pkgname-dev
"
source=https://ftp.gnu.org/gnu/libunistring/libunistring-1.3.tar.xz
sha256=f245786c831d25150f3dfb4317cda1acc5e3f79a5da4ad073ddca58886569527

depends=""

makedepends="
    binutils
    gawk
    gcc
    make
"

recipe_build()
{
	# Proven v0 flags: shared only.
	./configure 		--prefix=/usr 		--sysconfdir=/etc 		--localstatedir=/var 		--disable-static
	make
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
}
