#!/bin/sh
pkgname=jansson
pkgver=2.14.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='C library for encoding, decoding and manipulating JSON'
license='MIT'
origin=jansson
repo=saphira
url=https://github.com/akheron/jansson
jansson_sha256=979210eaffdffbcf54cfc34d047fccde13f21b529a381df26db871d886f729a4
depends=""
makedepends="cmake gcc make"
subpackages="$pkgname-dev"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/jansson-2.14.1.tar.gz"
	cmake -S "$SRC" -B "$BUILDDIR" \
		-DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DBUILD_SHARED_LIBS=ON \
		-DJANSSON_BUILD_DOCS=OFF \
		-DJANSSON_BUILD_TESTS=OFF
	cmake --build "$BUILDDIR" -j${JOBS:-$(nproc)}
}
recipe_install() {
	DESTDIR="$PKGDEST" cmake --install "$BUILDDIR"
}
