#!/bin/sh

pkgname=libwebp
pkgver=1.5.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="WebP image format library and conversion utilities"
license="BSD-3-Clause"
origin=libwebp
repo=saphira
url=https://developers.google.com/speed/webp
source=https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.5.0.tar.gz
sha256=7d6fab70cf844bf6769077bd5d7a74893f8ffd4dfb42861745750c63c2a5c92c

depends="
    libjpeg-turbo
    libpng
"

makedepends="
    binutils
    cmake
    gcc
    libjpeg-turbo-dev
    libpng
    make
    ninja
    pkgconf
"

# Development files ship in the main package; no -dev split.
recipe_build()
{
	cmake -S "$SRC" -B "$BUILDDIR" \
		-G Ninja \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DCMAKE_BUILD_TYPE=Release \
		-DBUILD_SHARED_LIBS=ON \
		-DWEBP_BUILD_CWEBP=ON -DWEBP_BUILD_DWEBP=ON \
		-DWEBP_BUILD_IMG2WEBP=ON -DWEBP_BUILD_WEBPINFO=ON \
		-DWEBP_BUILD_ANIM_UTILS=OFF -DWEBP_BUILD_EXTRAS=OFF \
		-DWEBP_BUILD_VWEBP=OFF
	ninja -C "$BUILDDIR"
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C "$BUILDDIR" install
}
