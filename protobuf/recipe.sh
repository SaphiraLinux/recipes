#!/bin/sh

pkgname=protobuf
pkgver=36.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Protocol Buffers runtime, protoc compiler and headers (C++)"
license="BSD-3-Clause"
origin=protobuf
repo=main
url=https://protobuf.dev/
vendor=https://github.com/protocolbuffers/protobuf/releases/download/v36.2/protobuf-36.2.tar.gz
sha256=3d9642a662d10e68ebae5e53f14dcce5105684212d5078f8e0d47d1ab3ae6b64

# Runtime edges are DT_NEEDED providers (abseil shared libs,
# libstdc++ via gcc-libs, zlib). RUNTIME gate verifies the closure.
depends="
    abseil-cpp
    gcc-libs
    zlib
"

makedepends="
    abseil-cpp-dev
    binutils
    cmake
    gcc
    make
    pkgconf
    zlib-dev
"

subpackages="
    $pkgname-dev
"

# Release tarball verified byte-identical against the upstream
# published sha256 (3d9642a6, printed on the release page).
# absl comes from the published abseil-cpp-dev (find_package CONFIG);
# LOCAL_DEPENDENCIES_ONLY fails closed instead of FetchContent-ing
# from GitHub (builds have no network by design). Tests, conformance
# and examples stay off (no consumer in the tree); shared libs on
# explicitly; zlib on (system). protoc ships in main (consumers and
# humans both invoke it).
recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/protobuf-36.2.tar.gz" | sha256sum -c -
	rm -rf "$BUILDDIR" && mkdir -p "$BUILDDIR"
	tar --no-same-owner -xf "$RECIPE_DIR/files/protobuf-36.2.tar.gz" \
		-C "$BUILDDIR" --strip-components=1
	cmake -S "$BUILDDIR" -B "$BUILDDIR/build" \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_CXX_STANDARD=17 \
		-Dprotobuf_LOCAL_DEPENDENCIES_ONLY=ON \
		-Dprotobuf_BUILD_TESTS=OFF \
		-Dprotobuf_BUILD_CONFORMANCE=OFF \
		-Dprotobuf_BUILD_EXAMPLES=OFF \
		-Dprotobuf_BUILD_SHARED_LIBS=ON \
		-Dprotobuf_WITH_ZLIB=ON
	cmake --build "$BUILDDIR/build"
}

recipe_install()
{
	DESTDIR="$PKGDEST" cmake --install "$BUILDDIR/build"
	# Payload proof: runtime objects, compiler, well-known-type
	# header (auto -dev split).
	for p in usr/lib/libprotobuf.so \
		usr/bin/protoc \
		usr/include/google/protobuf/message.h; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: protobuf payload is missing $p" >&2
			return 1
		}
	done
}
