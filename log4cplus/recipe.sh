#!/bin/sh

pkgname=log4cplus
pkgver=2.1.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="C++ logging library modelled on log4j"
license="Apache-2.0 OR BSD-2-Clause"
origin=log4cplus
repo=saphira
url=https://log4cplus.github.io/log4cplus/
source=https://github.com/log4cplus/log4cplus/releases/download/REL_2_1_2/log4cplus-2.1.2.tar.gz
sha256=e2673815ea34886f29b2213fff19cc1a6707a7e65099927a19ea49b4eb018822

subpackages="$pkgname-dev"
makedepends="
    binutils
    cmake
    gcc
    make
    ninja
"

# Development files ship in the main package; no -dev split.
recipe_build()
{
	cmake -G Ninja "$SRC" -B "$BUILDDIR" \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DCMAKE_BUILD_TYPE=Release \
		-DBUILD_SHARED_LIBS=ON \
		-DLOG4CPLUS_BUILD_TESTING=OFF \
		-DWITH_UNIT_TESTS=OFF \
		-DCMAKE_C_FLAGS="${CFLAGS-}" \
		-DCMAKE_CXX_FLAGS="${CXXFLAGS-}" \
		-DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS-}"
	ninja -C "$BUILDDIR"
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C "$BUILDDIR" install
}
