#!/bin/sh

pkgname=gtest
pkgver=1.18.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="GoogleTest and GoogleMock (C++17 test framework)"
license="BSD-3-Clause"
origin=gtest
repo=main
url=https://github.com/google/googletest
vendor=https://github.com/google/googletest/releases/download/v1.18.0/googletest-1.18.0.tar.gz
sha256=6e3191c1455468b3fc35a417fb565c1c5071aee1b7e7f85e30cf48a98d37d8b5

# Runtime edges are DT_NEEDED providers: every C++ shared object
# needs libstdc++.so.6/libgcc_s.so.1 from gcc-libs (llvm precedent).
depends="
    gcc-libs
"

makedepends="
    binutils
    cmake
    gcc
    make
"

subpackages="
    $pkgname-dev
"

# Shared libs on; gmock stays enabled (default) for consumers that
# need matchers. Own test suite not run at build (no consumer of
# test results in the tree; keeps the build hermetic and fast).
recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/googletest-1.18.0.tar.gz" | sha256sum -c -
	rm -rf "$BUILDDIR" && mkdir -p "$BUILDDIR"
	tar --no-same-owner -xf "$RECIPE_DIR/files/googletest-1.18.0.tar.gz" \
		-C "$BUILDDIR" --strip-components=1
	cmake -S "$BUILDDIR" -B "$BUILDDIR/build" \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_CXX_STANDARD=17 \
		-DBUILD_SHARED_LIBS=ON
	cmake --build "$BUILDDIR/build"
}

recipe_install()
{
	DESTDIR="$PKGDEST" cmake --install "$BUILDDIR/build"
	# Payload proof: both shared objects plus headers (auto -dev).
	for p in usr/lib/libgtest.so \
		usr/lib/libgmock.so \
		usr/include/gtest/gtest.h; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: gtest payload is missing $p" >&2
			return 1
		}
	done
}
