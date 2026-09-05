#!/bin/sh

pkgname=snappy
pkgver=1.2.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Fast compress/decompress library"
license="BSD-3-Clause"
origin=snappy
repo=saphira
url=https://github.com/google/snappy
source=https://github.com/google/snappy/archive/refs/tags/1.2.2.tar.gz
sha256=90f74bc1fbf78a6c56b3c4a082a05103b3a56bb17bca1a27e052ea11723292dc

makedepends="
    binutils
    cmake
    gcc
    make
    ninja
"

recipe_build()
{
	cmake -S "$SRC" -B "$BUILDDIR" \
		-G Ninja \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DCMAKE_BUILD_TYPE=Release \
		-DBUILD_SHARED_LIBS=ON \
		-DSNAPPY_INSTALL=ON \
		-DSNAPPY_BUILD_TESTS=OFF -DSNAPPY_BUILD_BENCHMARKS=OFF
	ninja -C "$BUILDDIR"
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C "$BUILDDIR" install
}
