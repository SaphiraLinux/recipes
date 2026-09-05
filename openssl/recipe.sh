#!/bin/sh
pkgname=openssl
pkgver=3.6.3
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='TLS/SSL and crypto library (Genesis base)'
license='Apache-2.0'
origin=openssl
repo=saphira
url=https://www.openssl.org/
openssl_sha256=243a86649cf6f23eeb6a2ff2456e09e5d77dd9018a54d3d96b0c6bdd6ba6c7f1
depends=""
makedepends="
	binutils
	gcc
	make
	perl
	zlib-dev
"
subpackages="$pkgname-dev"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/openssl-3.6.3.tar.gz"
	cd "$SRC"
	echo "$openssl_sha256  $RECIPE_DIR/files/openssl-3.6.3.tar.gz" | sha256sum -c -
	./Configure linux-x86_64 \
		--prefix=/usr --libdir=lib --openssldir=/etc/ssl \
		shared no-tests zlib
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install_sw install_ssldirs
	find "$PKGDEST" -name '*.la' -delete
}
