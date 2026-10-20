#!/bin/sh
pkgname=doxygen
pkgver=1.18.0
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Documentation generator (doxygen, for libssh/libepoxy API docs)'
license='GPL-2.0-or-later'
origin=doxygen
repo=saphira
url=https://www.doxygen.nl/
source=https://github.com/doxygen/doxygen/archive/refs/tags/Release_1_18_0.tar.gz
sha256=b32a3def78b0b75a2fd74ee6a63fb4a79cb6273fe31a570362e4e1871fa446da

# C++17 build (gcc 16 provides it). Bundled fmt/spdlog/sqlite3 are used
# (use_sys_* stay at upstream default off) and libclang parsing stays
# off (use_libclang default off) - no LLVM/Clang/fmt/spdlog/sqlite
# system deps needed. Only cmake+bison+flex+python from the tree.
# dot graphs degrade gracefully when graphviz is absent.
# r2: records the depends="gcc-libs" correction as its own revision.
# The C++ binary links libstdc++, so the runtime dep must be declared.
# r1 exists in two byte-different forms (pre/post correction, built
# minutes apart while the recipe changed mid-wave); r2 disambiguates
# all future builds so the publisher never sees same-NVR ambiguity.
depends="gcc-libs"
makedepends="
	binutils
	bison
	cmake
	flex
	gcc
	make
	ninja
	python3
	pkgconf
"

subpackages="$pkgname-doc"

recipe_build()
{
	cmake -S "$SRC" -B "$BUILDDIR" \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX=/usr
	cmake --build "$BUILDDIR" -j${JOBS:-$(nproc)}
}

recipe_install()
{
	DESTDIR="$PKGDEST" cmake --install "$BUILDDIR"
}
