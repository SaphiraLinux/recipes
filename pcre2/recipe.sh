#!/bin/sh
pkgname=pcre2
pkgver=10.47
pkgrel=4
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Perl-compatible regular expression library v2'
license='BSD-3-Clause'
origin=pcre2
repo=saphira
url=https://www.pcre.org/
pcre2_sha256=47fe8c99461250d42f89e6e8fdaeba9da057855d06eb7fc08d9ca03fd08d7bc7
depends=""
makedepends="cmake gcc make"
subpackages="$pkgname-dev"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/pcre2-10.47.tar.bz2"
	cmake -S "$SRC" -B "$BUILDDIR" \
		-DCMAKE_C_COMPILER=gcc -DCMAKE_BUILD_TYPE=Release \
		-DBUILD_SHARED_LIBS=ON \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DPCRE2_BUILD_PCRE2GREP=ON \
		-DPCRE2_SUPPORT_JIT=ON \
		-DPCRE2_BUILD_TESTS=OFF
	cmake --build "$BUILDDIR" -j${JOBS:-$(nproc)}
}
recipe_install() {
	DESTDIR="$PKGDEST" cmake --install "$BUILDDIR"
}
