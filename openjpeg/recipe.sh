#!/bin/sh

pkgname=openjpeg
pkgver=2.5.4
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="JPEG 2000 codec library and tools (with OSV-2025-219 backport)"
license='BSD-2-Clause'
origin=openjpeg
repo=saphira
url=https://www.openjpeg.org/
source=https://github.com/uclouvain/openjpeg/archive/refs/tags/v2.5.4.tar.gz
sha256=a695fbe19c0165f295a8531b1e4e855cd94d0875d2f88ec4b61080677e27188a

# Upstream 2.5.4 is the newest tag but the project is unmaintained and
# a February 2026 heap-overflow fix (OSV-2025-219, opj_j2k_read_sod
# tile-part index write) never shipped in any release. The backport
# below applies cleanly to 2.5.4 and is verified at patch time.
depends="
    libpng
    libtiff
    lcms2
    zlib
"

makedepends="
    binutils
    cmake
    gcc
    libpng
    libtiff-dev
    lcms2-dev
    zlib-dev
    make
    ninja
    pkgconf
"

subpackages="$pkgname-dev $pkgname-doc"

recipe_build()
{
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/v2.5.4.tar.gz"
	echo "$sha256  $RECIPE_DIR/files/v2.5.4.tar.gz" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$RECIPE_DIR/files/osv-2025-219-heap-overflow.patch" || {
		echo "ERROR: OSV-2025-219 backport does not apply" >&2
		return 1
	}
	cmake -S "$SRC" -B "$BUILDDIR" \
		-G Ninja \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DCMAKE_BUILD_TYPE=Release \
		-DBUILD_SHARED_LIBS=ON \
		-DBUILD_CODEC=ON \
		-DBUILD_TESTING=OFF
	ninja -C "$BUILDDIR"
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C "$BUILDDIR" install
	test -x "$PKGDEST/usr/bin/opj_decompress" || {
		echo "ERROR: staged payload is missing the openjpeg tools" >&2
		return 1
	}
	test -f "$SRC/LICENSE" || {
		echo "ERROR: upstream licence file missing from source tree" >&2
		return 1
	}
	install -D -m 0644 "$SRC/LICENSE" \
		"$PKGDEST/usr/share/licenses/openjpeg/LICENSE"
}
