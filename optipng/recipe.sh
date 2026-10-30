#!/bin/sh

pkgname=optipng
pkgver=7.9.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Lossless PNG optimizer and inspector"
license='Zlib'
origin=optipng
repo=saphira
url=https://optipng.sourceforge.net/
source=https://download.sourceforge.net/project/optipng/optipng-7.9.1.tar.gz
sha256=c2579be58c2c66dae9d63154edcb3d427fef64cb00ec0aff079c9d156ec46f29

depends="
    libpng
    zlib
"

makedepends="
    binutils
    cmake
    gcc
    libpng
    zlib-dev
    make
    ninja
    pkgconf
"

recipe_build()
{
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/optipng-7.9.1.tar.gz"
	echo "$sha256  $RECIPE_DIR/files/optipng-7.9.1.tar.gz" | sha256sum -c -
	# OPTIPNG_USE_SYSTEM_LIBS is load-bearing: the default builds
	# and installs third-party zlib AND libpng trees (vendored
	# libz.so* landed in the payload before this flag). Tests off:
	# unit-test binaries are build-time only, never payload.
	cmake -S "$SRC" -B "$BUILDDIR" \
		-G Ninja \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DCMAKE_BUILD_TYPE=Release \
		-DOPTIPNG_USE_SYSTEM_LIBS=ON \
		-DOPTIPNG_BUILD_TESTS=OFF
	ninja -C "$BUILDDIR"
}

recipe_install()
{
	# Explicit staging (not ninja install): only the tool and its
	# manual page are payload, never third-party anything.
	install -D -m 0755 "$BUILDDIR/optipng" \
		"$PKGDEST/usr/bin/optipng"
	install -D -m 0644 "$SRC/src/optipng/man/optipng.1" \
		"$PKGDEST/usr/share/man/man1/optipng.1" 2>/dev/null || true
	test -x "$PKGDEST/usr/bin/optipng" || {
		echo "ERROR: staged payload is missing usr/bin/optipng" >&2
		return 1
	}
	test -f "$SRC/LICENSE.txt" || {
		echo "ERROR: upstream licence file missing from source tree" >&2
		return 1
	}
	install -D -m 0644 "$SRC/LICENSE.txt" \
		"$PKGDEST/usr/share/licenses/optipng/LICENSE.txt"
}
