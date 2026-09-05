#!/bin/sh

pkgname=libgeoip
pkgver=1.6.12
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="GeoIP legacy library for resolving IP addresses to countries"
license="LGPL-2.1-or-later"
origin=libgeoip
repo=main
url=https://github.com/maxmind/geoip-api-c
source=https://github.com/maxmind/geoip-api-c/releases/download/v1.6.12/GeoIP-1.6.12.tar.gz
sha256=1dfb748003c5e4b7fd56ba8c4cd786633d5d6f409547584f6910398389636f80

depends="zlib"

makedepends="
    binutils
    gcc
    make
    zlib-dev
"

recipe_build()
{
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	"$SRC/configure" --prefix=/usr --disable-static
	make
}

recipe_install()
{
	make -C "$BUILDDIR" DESTDIR="$PKGDEST" install
}
