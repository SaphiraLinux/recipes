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
# download.savannah.gnu.org challenges this network; the savannah canonical
# and download-mirror endpoints were verified byte-identical 2026-09-10.
# Upstream re-gzipped lzip-1.25 (same tree, new bytes): pin follows what
# both endpoints serve.
source=https://download.savannah.gnu.org/releases/lzip/lzip-1.25.tar.gz
sha256=09418a6d8fb83f5113f5bd856e09703df5d37bae0308c668d0f346e3d3f0a56f

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
