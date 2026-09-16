#!/bin/sh

pkgname=cmake
pkgver=4.4.1
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Cross-platform build system generator"
license="BSD-3-Clause"
origin=cmake
repo=main
url=https://cmake.org/
# cmake.org serves a bot-challenge page to this network; the GitHub
# release archive is byte-equivalent source.
source=https://github.com/Kitware/CMake/archive/refs/tags/v${pkgver}.tar.gz
sha256=33b21b0be53eb10adcf2f2aaa40e2d62017e9b5c82610528d4051aa17e02cf04

depends="
    curl
"

makedepends="
    binutils
    curl-dev
    gawk
    gcc
    make
"

recipe_build()
{
	# Bootstrap path needs only gcc/make; C++17-capable compiler present.
	# libcurl HTTPS support on: curl-dev is live, and upstream CMake
	# functionality stays enabled when a dependency exists - the native
	# builder resolving sources itself is no reason to cripple the tool
	# (FetchContent-capable cmake is normal upstream behavior).
	./bootstrap --prefix=/usr --parallel="${JOBS:-4}" --system-curl \
		-- -DCMAKE_USE_OPENSSL=ON -DBUILD_CursesDialog=OFF \
		-DCMAKE_C_FLAGS="${CFLAGS-}" -DCMAKE_CXX_FLAGS="${CXXFLAGS-}" \
		-DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS-}"
	make
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
}
