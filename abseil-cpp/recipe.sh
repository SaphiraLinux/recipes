#!/bin/sh

pkgname=abseil-cpp
pkgver=20260817.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Abseil common libraries (C++, LTS Aug 2026; protobuf prerequisite)"
license="Apache-2.0"
origin=abseil-cpp
repo=main
url=https://abseil.io/
vendor=https://github.com/abseil/abseil-cpp/releases/download/20260817.0/abseil-cpp-20260817.0.tar.gz
sha256=f7e05179df39c45434cad433f5783840bb3788ef322976f9138bc6b72b3a107d

# Runtime edges are DT_NEEDED providers: every C++ shared object
# needs libstdc++.so.6/libgcc_s.so.1 from gcc-libs (llvm precedent:
# its r4 added exactly this edge for the same closure failure).
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

# LTS snapshot (not live-at-head): packaged-dependency stability over
# novelty. Shared libs on (consumers link shared); tests and test
# helpers off (no test consumer in the tree); install enabled (the
# CMake config + headers protobuf resolves live in the auto -dev
# split); C++17 floor matches the lowest consumer (gtest/protobuf).
recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/abseil-cpp-20260817.0.tar.gz" | sha256sum -c -
	rm -rf "$BUILDDIR" && mkdir -p "$BUILDDIR"
	tar --no-same-owner -xf "$RECIPE_DIR/files/abseil-cpp-20260817.0.tar.gz" \
		-C "$BUILDDIR" --strip-components=1
	cmake -S "$BUILDDIR" -B "$BUILDDIR/build" \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_CXX_STANDARD=17 \
		-DBUILD_SHARED_LIBS=ON \
		-DABSL_ENABLE_INSTALL=ON \
		-DABSL_BUILD_TESTING=OFF \
		-DABSL_BUILD_TEST_HELPERS=OFF
	cmake --build "$BUILDDIR/build"
}

recipe_install()
{
	DESTDIR="$PKGDEST" cmake --install "$BUILDDIR/build"
	# Payload proof: a representative shared object, a header and
	# the CMake config downstreams resolve (auto -dev split).
	for p in usr/lib/libabsl_strings.so \
		usr/include/absl/strings/string_view.h \
		usr/lib/cmake/absl/abslConfig.cmake; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: abseil-cpp payload is missing $p" >&2
			return 1
		}
	done
}
