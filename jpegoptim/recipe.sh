#!/bin/sh

pkgname=jpegoptim
pkgver=1.5.6
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Lossless JPEG optimizer (system libjpeg-turbo, no downloads)"
license='GPL-3.0-or-later'
origin=jpegoptim
repo=saphira
url=https://github.com/tjko/jpegoptim
source=https://github.com/tjko/jpegoptim/archive/refs/tags/v1.5.6.tar.gz
sha256=661a808dfffa933d78c6beb47a2937d572b9f03e94cbaaab3d4c0d72f410e9be

depends="libjpeg-turbo"

makedepends="
    binutils
    cmake
    gcc
    libjpeg-turbo-dev
    make
    ninja
    pkgconf
"

recipe_build()
{
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/v1.5.6.tar.gz"
	echo "$sha256  $RECIPE_DIR/files/v1.5.6.tar.gz" | sha256sum -c -
	# USE_MOZJPEG=OFF is load-bearing: upstream default downloads,
	# builds and links MozJPEG at build time. Saphira uses the system
	# libjpeg-turbo unconditionally (network fetching at build time
	# is forbidden).
	cmake -S "$SRC" -B "$BUILDDIR" \
		-G Ninja \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DCMAKE_BUILD_TYPE=Release \
		-DUSE_MOZJPEG=OFF \
		-DBUILD_FUZZERS=OFF
	ninja -C "$BUILDDIR"
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C "$BUILDDIR" install
	# The tool must actually be staged (no silent no-op install).
	test -x "$PKGDEST/usr/bin/jpegoptim" || {
		echo "ERROR: staged payload is missing usr/bin/jpegoptim" >&2
		return 1
	}
	test -f "$SRC/LICENSE" || {
		echo "ERROR: upstream licence file missing from source tree" >&2
		return 1
	}
	install -D -m 0644 "$SRC/LICENSE" \
		"$PKGDEST/usr/share/licenses/jpegoptim/LICENSE"
}
