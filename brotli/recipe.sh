#!/bin/sh

pkgname=brotli
pkgver=1.2.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Generic-purpose lossless compression (RFC 7932), libraries and CLI'
license='MIT'
origin=brotli
repo=saphira
url=https://github.com/google/brotli
# Vendored: https://github.com/google/brotli/archive/refs/tags/v1.2.1.tar.gz
brotli_sha256=98d35d11a78dc453aebb7d10c3748f3f73ff78c8267c0dc697b8631f67bf7e8f

depends=""
makedepends="
	binutils
	cmake
	gcc
	make
	ninja
"
subpackages="$pkgname-dev $pkgname-doc"

recipe_build()
{
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/brotli-1.2.1.tar.gz"
	cd "$SRC"
	echo "$brotli_sha256  $RECIPE_DIR/files/brotli-1.2.1.tar.gz" | sha256sum -c -
	cmake -S "$SRC" -B "$BUILDDIR" \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_LIBDIR=lib
	cmake --build "$BUILDDIR" -j${JOBS:-$(nproc)}
}

recipe_install()
{
	DESTDIR="$PKGDEST" cmake --install "$BUILDDIR"
	rm -f "$PKGDEST/usr/lib"/libbrotli*.a
	# FHS non-usrmerged: brotli is also an nginx runtime dependency
	# (ngx_brotli dynamic module, loaded from /usr/sbin); the versioned
	# runtime stays addressable via the standard /usr/lib path used by
	# /usr binaries. No /bin|/sbin consumer exists, so /usr/lib is
	# correct for this library.
}
