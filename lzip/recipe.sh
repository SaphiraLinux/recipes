#!/bin/sh

pkgname=lzip
pkgver=1.25
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Lossless file compressor with a simple LZMA-based format"
license="GPL-2.0-or-later"
origin=lzip
repo=main
url=https://www.nongnu.org/lzip/
# download.savannah.gnu.org challenges this network; kernel.org mirror
# verified byte-equivalent.
source=https://download.savannah.gnu.org/releases/lzip/lzip-1.25.tar.gz
sha256=5db7a6ea9a3d4878b7f6ec0d2dca330b9a09a26b1336cec59586205253e7504c

depends=""

makedepends="
    gcc
    make
"

recipe_build()
{
	./configure --prefix=/usr CXX="${CXX:-g++}" \
		CXXFLAGS="${CXXFLAGS:--O2} ${LDFLAGS-}"
	make
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
}
