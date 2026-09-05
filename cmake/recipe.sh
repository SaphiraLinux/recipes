#!/bin/sh

pkgname=cmake
pkgver=4.4.1
pkgrel=1
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

depends=""

makedepends="
    binutils
    gawk
    gcc
    make
"

recipe_build()
{
	# Bootstrap path needs only gcc/make; C++17-capable compiler present.
	# HTTPS download support stays off until libcurl is packaged; the
	# native builder resolves sources outside cmake anyway.
	./bootstrap --prefix=/usr --parallel="${JOBS:-4}" \
		-- -DCMAKE_USE_OPENSSL=OFF -DBUILD_CursesDialog=OFF \
		-DCMAKE_C_FLAGS="${CFLAGS-}" -DCMAKE_CXX_FLAGS="${CXXFLAGS-}" \
		-DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS-}"
	make
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
}
