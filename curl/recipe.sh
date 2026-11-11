#!/bin/sh
pkgname=curl
pkgver=8.22.0
# 8.22.0: 31-CVE batch (Nov 2026), incl. critical HTTP/2 upload
# use-after-free CVE-2026-92392 (code exec via malicious server)
# plus auth/cookie/protocol handling fixes. New upstream version:
# pkgrel resets to 1.
# r5: no LDAP/LDAPS (author decision 2026-11-06): directory access
# has no place in base curl - the openldap runtime closure (server,
# perl, libtool, argon2) does not belong on every machine that
# fetches over HTTPS. LDAP clients use the openldap package/tools
# directly. --disable-ldap/--disable-ldaps, openldap gone from
# depends and makedepends; the feature proof below asserts absence.
# r4: LDAP/LDAPS via OpenLDAP client libs (openldap runtime only,
# never the server), and ship the built-in manual (curl --manual).
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='URL transfer utility and library'
license='curl'
origin=curl
repo=saphira
url=https://curl.se/
curl_sha256=f7ef3ae8a22e521f289803fe93543eb64c329b58aa73a9e224dfd915a2a5f4f7
depends="openssl zlib zstd brotli nghttp2 libidn2"
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
	libunistring-dev
"
depends_dev="openssl-dev zlib-dev zstd-dev brotli-dev nghttp2 libidn2-dev libunistring-dev"
subpackages="$pkgname-dev"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/curl-8.22.0.tar.xz"
	cd "$SRC"
	echo "$curl_sha256  $RECIPE_DIR/files/curl-8.22.0.tar.xz" | sha256sum -c -
	./configure --prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--with-openssl \
		--with-brotli --with-nghttp2 --with-libidn2 \
		--disable-ldap --disable-ldaps \
		--disable-static \
		--without-libpsl --without-librtmp
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
	find "$PKGDEST" -name '*.la' -delete
	# Feature proof (RECIPE_RULES: verify intended features shipped):
	# the just-built binary must advertise Brotli, HTTP/2 and IDN,
	# must NOT advertise LDAP (author decision: no directory access
	# in base curl), and carry a working built-in manual.
	# It links the just-built libcurl, which lives only under $PKGDEST
	# at proof time, so put it on the loader path first: otherwise the
	# proof tests Egg's installed libcurl (or fails outright in the
	# isolated build root) instead of what was just built.
	# Plain grep (no -q): under the worker's pipefail, grep -q quits
	# early and the producer dies of SIGPIPE, failing the pipeline
	# despite a match.
	export LD_LIBRARY_PATH="$PKGDEST/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
	features=$("$PKGDEST/usr/bin/curl" -V)
	printf '%s\n' "$features" | grep 'brotli' > /dev/null || \
		{ printf 'curl: brotli support missing\n' >&2; exit 1; }
	printf '%s\n' "$features" | grep 'nghttp2' > /dev/null || \
		{ printf 'curl: HTTP/2 (nghttp2) support missing\n' >&2; exit 1; }
	printf '%s\n' "$features" | grep -w 'IDN' > /dev/null || \
		{ printf 'curl: IDN support missing\n' >&2; exit 1; }
	for proto in ldap ldaps; do
		printf '%s\n' "$features" | grep -w "$proto" > /dev/null && \
			{ printf 'curl: LDAP protocol %s present but excluded\n' "$proto" >&2; exit 1; }
	done
	printf '%s\n' 'ok: LDAP absent as configured' >&2
	"$PKGDEST/usr/bin/curl" --manual > /dev/null || \
		{ printf 'curl: built-in manual broken\n' >&2; exit 1; }
}
