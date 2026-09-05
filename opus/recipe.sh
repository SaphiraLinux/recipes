#!/bin/sh

pkgname=opus
pkgver=1.5.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Codec designed for interactive speech and audio transmission'
license='BSD-3-Clause'
origin=opus
repo=saphira
url=https://www.opus-codec.org/
# Vendored: https://downloads.xiph.org/releases/opus/opus-1.5.2.tar.gz
opus_sha256=65c1d2f78b9f2fb20082c38cbe47c951ad5839345876e46941612ee87f9a7ce1

depends=""
makedepends="
	binutils
	cmake
	gcc
	make
	ninja
	pkgconf
"

subpackages="$pkgname-dev"

recipe_build()
{
	OPBALL="$RECIPE_DIR/files/opus-1.5.2.tar.gz"
	echo "$opus_sha256  $OPBALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$OPBALL"
	cmake -S "$SRC" -B "$BUILDDIR" \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DOPUS_BUILD_SHARED_LIBRARY=ON \
		-DOPUS_BUILD_TESTING=OFF \
		-DOPUS_BUILD_PROGRAMS=OFF \
		-DOPUS_ENABLE_FLOAT_API=ON \
		-DOPUS_INSTALL_PKG_CONFIG_MODULE=ON
	cmake --build "$BUILDDIR" -j${JOBS:-$(nproc)}
}

recipe_install()
{
	DESTDIR="$PKGDEST" cmake --install "$BUILDDIR"
}
