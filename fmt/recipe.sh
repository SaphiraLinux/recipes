#!/bin/sh
pkgname=fmt
pkgver=12.1.0
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Modern C++ formatting library'
license='MIT OR BSD-2-Clause'
origin=fmt
repo=saphira
url=https://github.com/fmtlib/fmt
fmt_sha256=ea7de4299689e12b6dddd392f9896f08fb0777ac7168897a244a6d6085043fea
depends="gcc-libs"
makedepends="cmake gcc make"
subpackages="$pkgname-dev"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/fmt-12.1.0.tar.gz"
	cmake -S "$SRC" -B "$BUILDDIR" \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DBUILD_SHARED_LIBS=ON \
		-DFMT_TEST=OFF \
		-DFMT_DOC=OFF
	cmake --build "$BUILDDIR" -j${JOBS:-$(nproc)}
}
recipe_install() {
	DESTDIR="$PKGDEST" cmake --install "$BUILDDIR"
}
