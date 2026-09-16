#!/bin/sh

pkgname=c-ares
pkgver=1.34.8
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Asynchronous DNS resolver library (nghttpx/nghttp apps need it)"
license="MIT"
origin=c-ares
repo=saphira
url=https://c-ares.org/
source=https://github.com/c-ares/c-ares/releases/download/v1.34.8/c-ares-1.34.8.tar.gz
sha256=c222b6d681096f9444d2c4863d2c1174019e27cacca0a4a5c114d36dd7d7bf78

depends=""

makedepends="
    binutils
    cmake
    gcc
    make
"

subpackages="c-ares-dev"

# Release asset tarball (not the auto-generated git archive, which
# GitHub mangles the way nghttp2's tag archives are mangled).
recipe_build()
{
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	cmake "$SRC" \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DCMAKE_BUILD_TYPE=Release \
		-DCARES_SHARED=ON \
		-DCARES_STATIC=OFF
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$BUILDDIR" DESTDIR="$PKGDEST" install
}
