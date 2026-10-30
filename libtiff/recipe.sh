#!/bin/sh

pkgname=libtiff
pkgver=4.7.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="TIFF image library and utilities (tiffcp, tiffinfo and friends)"
license='libtiff'
origin=libtiff
repo=saphira
url=https://libtiff.gitlab.io/libtiff/
source=https://download.osgeo.org/libtiff/tiff-4.7.2.tar.gz
sha256=672bd7d10aee4606171afb864f3570b83340f6a33e2c186dc0512f7145ffdf6a

# Codec support follows what exists in-tree: JPEG (turbo), zlib,
# WebP and zstd stay on; JBIG-KIT, libdeflate and LZMA-adjacent extras
# have no recipe and stay off via auto-detection (never force-enabled).
# libwebp ships its headers in main (no -dev split); xz-dev and
# zstd-dev splits exist.
# Several tools link C++ (libstdc++/libgcc_s): the RUNTIME gate
# requires them declared (same lesson as llvm/nodejs).
depends="
    libjpeg-turbo
    zlib
    libwebp
    zstd
    xz
    gcc-libs
"

makedepends="
    binutils
    cmake
    gcc
    libjpeg-turbo-dev
    zlib-dev
    libwebp
    zstd-dev
    xz-dev
    make
    ninja
    pkgconf
"

subpackages="$pkgname-dev $pkgname-doc"

recipe_build()
{
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/tiff-4.7.2.tar.gz"
	echo "$sha256  $RECIPE_DIR/files/tiff-4.7.2.tar.gz" | sha256sum -c -
	cmake -S "$SRC" -B "$BUILDDIR" \
		-G Ninja \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DCMAKE_BUILD_TYPE=Release \
		-DBUILD_SHARED_LIBS=ON \
		-Dtiff-tools=ON \
		-Dtiff-tests=OFF \
		-Dtiff-contrib=ON \
		-Dtiff-docs=OFF
	ninja -C "$BUILDDIR"
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C "$BUILDDIR" install
	# The tools are the point of the "and friends" in pkgdesc.
	test -x "$PKGDEST/usr/bin/tiffinfo" || {
		echo "ERROR: staged payload is missing the tiff tools" >&2
		return 1
	}
	test -f "$SRC/LICENSE.md" || {
		echo "ERROR: upstream licence file missing from source tree" >&2
		return 1
	}
	install -D -m 0644 "$SRC/LICENSE.md" \
		"$PKGDEST/usr/share/licenses/libtiff/LICENSE.md"
}
