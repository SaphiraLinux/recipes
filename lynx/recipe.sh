#!/bin/sh

pkgname=lynx
pkgver=2.9.3
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Lynx: general-purpose text-mode web browser"
license="GPL-2.0-or-later"
origin=lynx
repo=saphira
url=https://lynx.invisible-island.net/
source=https://invisible-island.net/archives/lynx/tarballs/lynx2.9.3.tar.bz2
sha256=174b7f2866a60f3247ba75f5c7dbb10b124aede4a1359312de15f3bfebd2050f

makedepends="
    binutils
    gcc
    make
    ncurses-dev
    openssl-dev
    zlib-dev
"

recipe_build()
{
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	"$SRC/configure" --prefix=/usr --enable-widec --enable-ipv6 \
		--with-ssl --with-zlib
	make
}

recipe_install()
{
	make -C "$BUILDDIR" DESTDIR="$PKGDEST" install
}
