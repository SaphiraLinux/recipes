#!/bin/sh

pkgname=binaryen
pkgver=131
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Compiler infrastructure and toolchain library for WebAssembly (wasm-opt, wasm-as, ...)'
license='Apache-2.0'
origin=binaryen
repo=saphira
url=https://github.com/WebAssembly/binaryen
source=https://github.com/WebAssembly/binaryen/archive/refs/tags/version_${pkgver}.tar.gz
sha256=3274719775038062b62d2bf2b37dcde69f3f79804aeb7420b78926722c0d0065

depends=""
makedepends="
	cmake
	gcc
	make
"

# Install prefix follows the old-gen layout: the binaryen tools belong to
# the emscripten toolchain tree. Submodules (googletest/fuzztest) are not
# vendored: tests and fuzzing are disabled, so they are not required.
recipe_build()
{
	cmake -S "$SRC" -B "$BUILDDIR" \
		-DCMAKE_INSTALL_PREFIX=/usr/lib/emscripten-toolchain \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_SKIP_RPATH=ON \
		-DCMAKE_CXX_FLAGS="-Wno-error=array-bounds" \
		-DBUILD_TESTS=OFF \
		-DBUILD_FUZZTEST=OFF \
		-DBUILD_MIMALLOC=OFF \
		-DBUILD_TOOLS=ON
	cmake --build "$BUILDDIR" -j${JOBS:-$(nproc)}
}

recipe_install()
{
	DESTDIR="$PKGDEST" cmake --install "$BUILDDIR"
	LD_LIBRARY_PATH="$BUILDDIR/lib" \
		"$PKGDEST/usr/lib/emscripten-toolchain/bin/wasm-opt" --version
}
