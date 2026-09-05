#!/bin/sh

pkgname=libjpeg-turbo
pkgver=3.1.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Accelerated JPEG codec library'
license='IJG OR BSD-3-Clause OR Zlib'
origin=libjpeg-turbo
repo=saphira
url=https://libjpeg-turbo.org/
# Vendored: https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/3.1.2/libjpeg-turbo-3.1.2.tar.gz
libjpeg_turbo_sha256=8f0012234b464ce50890c490f18194f913a7b1f4e6a03d6644179fa0f867d0cf

depends=""
makedepends="
	binutils
	cmake
	gcc
	make
	ninja
"

subpackages="$pkgname-dev"

recipe_build()
{
	LJBALL="$RECIPE_DIR/files/libjpeg-turbo-3.1.2.tar.gz"
	echo "$libjpeg_turbo_sha256  $LJBALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$LJBALL"
	cmake -S "$SRC" -B "$BUILDDIR" \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DWITH_CRT=OFF \
		-DWITH_JAVA=OFF \
		-DWITH_TURBOJPEG=OFF
	cmake --build "$BUILDDIR" -j${JOBS:-$(nproc)}
}

recipe_install()
{
	DESTDIR="$PKGDEST" cmake --install "$BUILDDIR"
}
