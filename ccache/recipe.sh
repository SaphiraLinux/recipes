#!/bin/sh

pkgname=ccache
pkgver=4.13.6
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Fast C/C++ compiler cache'
license='GPL-3.0-or-later'
origin=ccache
repo=saphira
url=https://ccache.dev/
# Vendored: https://github.com/ccache/ccache/releases/download/v4.13.6/ccache-4.13.6.tar.xz
ccache_sha256=a7de667ca08cf67c3c8af9f213f6aa701a1188a2b3163fb74483858ce5e79fbb

depends="xxhash zstd"
makedepends="
	binutils
	cmake
	gcc
	gzip
	make
	ninja
	perl
	pkgconf
	python3
	xxhash-dev
	zstd-dev
"

recipe_build()
{
	CCBALL="$RECIPE_DIR/files/ccache-4.13.6.tar.xz"
	echo "$ccache_sha256  $CCBALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$CCBALL"
	cmake -S "$SRC" -B "$BUILDDIR" \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DENABLE_TESTING=OFF \
		-DREDIS_STORAGE_BACKEND=OFF \
		-DZSTD_FROM_INTERNET=OFF \
		-DDEPS=LOCAL
	cmake --build "$BUILDDIR" -j${JOBS:-$(nproc)}
}

recipe_install()
{
	DESTDIR="$PKGDEST" cmake --install "$BUILDDIR"
	# Masquerade dir: PATH-prefixing this transparently routes
	# compiler invocations through ccache without touching recipes.
	install -d "$PKGDEST/usr/lib/ccache/bin"
	for c in gcc g++ cc c++ clang clang++; do
		ln -sf ../../../bin/ccache "$PKGDEST/usr/lib/ccache/bin/$c"
	done
}
