#!/bin/sh
pkgname=curl
pkgver=8.20.0
# r4: LDAP/LDAPS via OpenLDAP client libs (openldap runtime only,
# never the server), and ship the built-in manual (curl --manual).
pkgrel=4
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='URL transfer utility and library'
license='curl'
origin=curl
repo=saphira
url=https://curl.se/
curl_sha256=63fe2dc148ba0ceae89922ef838f7e5c946272c2e78b7c59fab4b79d3ce2b896
depends="openssl zlib zstd brotli nghttp2 libidn2 openldap"
makedepends="
	gawk
	gcc
	make
	openssl-dev
	pkgconf
	zlib-dev
	zstd-dev
	brotli-dev
	nghttp2
	libidn2-dev
	openldap-dev
"
depends_dev="openssl-dev zlib-dev zstd-dev brotli-dev nghttp2 libidn2-dev openldap-dev"
subpackages="$pkgname-dev"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/curl-8.20.0.tar.xz"
	cd "$SRC"
	echo "$curl_sha256  $RECIPE_DIR/files/curl-8.20.0.tar.xz" | sha256sum -c -
	./configure --prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--with-openssl \
		--with-brotli --with-nghttp2 --with-libidn2 \
		--enable-ldap --enable-ldaps \
		--disable-static \
		--without-libpsl --without-librtmp
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
	find "$PKGDEST" -name '*.la' -delete
	# Feature proof (RECIPE_RULES: verify intended features shipped):
	# the just-built binary must advertise Brotli, HTTP/2, IDN and the
	# LDAP protocol family, and carry a working built-in manual.
	# Plain grep (no -q): under the worker's pipefail, grep -q quits
	# early and the producer dies of SIGPIPE, failing the pipeline
	# despite a match.
	features=$("$PKGDEST/usr/bin/curl" -V)
	printf '%s\n' "$features" | grep 'brotli' > /dev/null || \
		{ printf 'curl: brotli support missing\n' >&2; exit 1; }
	printf '%s\n' "$features" | grep 'nghttp2' > /dev/null || \
		{ printf 'curl: HTTP/2 (nghttp2) support missing\n' >&2; exit 1; }
	printf '%s\n' "$features" | grep -w 'IDN' > /dev/null || \
		{ printf 'curl: IDN support missing\n' >&2; exit 1; }
	for proto in ldap ldaps; do
		printf '%s\n' "$features" | grep -w "$proto" > /dev/null || \
			{ printf 'curl: protocol %s missing\n' "$proto" >&2; exit 1; }
	done
	"$PKGDEST/usr/bin/curl" --manual > /dev/null || \
		{ printf 'curl: built-in manual broken\n' >&2; exit 1; }
}
