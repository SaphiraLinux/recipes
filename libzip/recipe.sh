#!/bin/sh

pkgname=libzip
pkgver=1.11.4
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='C library for reading, creating and modifying zip archives'
license='BSD-3-Clause'
origin=libzip
repo=saphira
url=https://libzip.org/
source=https://github.com/nih-at/libzip/releases/download/v${pkgver}/libzip-${pkgver}.tar.gz
sha256=82e9f2f2421f9d7c2466bbc3173cd09595a88ea37db0d559a9d0a2dc60dc722e

depends="zlib musl-fts bzip2 xz zstd openssl"
depends_dev="musl-fts-dev bzip2-dev xz-dev zstd-dev openssl-dev"
makedepends="
	cmake
	gcc
	make
	zlib-dev
	musl-fts-dev
	bzip2-dev
	xz-dev
	zstd-dev
	openssl-dev
"

subpackages="$pkgname-dev"

# Full codec scope: bzip2, lzma, zstd and OpenSSL crypto (zip AES
# encryption) — all four backing stacks are native now.
recipe_build()
{
	cmake -S "$SRC" -B "$BUILDDIR" \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DCMAKE_BUILD_TYPE=Release \
		-DBUILD_DOC=OFF \
		-DBUILD_EXAMPLES=OFF \
		-DBUILD_REGRESS=OFF \
		-DENABLE_BZIP2=ON \
		-DENABLE_LZMA=ON \
		-DENABLE_ZSTD=ON \
		-DENABLE_OPENSSL=ON \
		-DENABLE_GNUTLS=OFF \
		-DENABLE_MBEDTLS=OFF \
		-DENABLE_COMMONCRYPTO=OFF
	cmake --build "$BUILDDIR" -j${JOBS:-$(nproc)}
}

recipe_install()
{
	DESTDIR="$PKGDEST" cmake --install "$BUILDDIR"
	find "$PKGDEST" -name '*.la' -delete
	test -e "$PKGDEST/usr/lib/libzip.so"
}
