#!/bin/sh
pkgname=curl
pkgver=8.20.0
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='URL transfer utility and library'
license='curl'
origin=curl
repo=saphira
url=https://curl.se/
curl_sha256=63fe2dc148ba0ceae89922ef838f7e5c946272c2e78b7c59fab4b79d3ce2b896
depends="openssl zlib zstd"
makedepends="
	gawk
	gcc
	make
	openssl-dev
	pkgconf
	zlib-dev
	zstd-dev
"
depends_dev="openssl-dev zlib-dev zstd-dev"
subpackages="$pkgname-dev"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/curl-8.20.0.tar.xz"
	cd "$SRC"
	echo "$curl_sha256  $RECIPE_DIR/files/curl-8.20.0.tar.xz" | sha256sum -c -
	./configure --prefix=/usr \
		--with-openssl \
		--disable-static --disable-ldap --disable-ldaps \
		--without-brotli --without-nghttp2 --without-libpsl --without-librtmp --without-libidn2 \
		--disable-manual
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
	find "$PKGDEST" -name '*.la' -delete
}
