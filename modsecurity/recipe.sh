#!/bin/sh

# libmodsecurity v3.0.16: the ModSecurity WAF engine as a C++ library.
#
# Deliberately the v3 line, NOT v2.9.14: v2 is the Apache module line
# and the CRS project does not support nginx+v2 ("do not work as
# expected... avoid these setups"); Saphira has no Apache and the
# stated targets are nginx and haproxy. For nginx the supported
# pairing is v3 + the ModSecurity-nginx connector (separate
# nginx-mod-modsecurity package, --add-dynamic-module against the
# nginx source); for haproxy it is coraza-spoa.
# v2.9.14 would have no consumer here.
#
# Release tarball is self-contained: others/libinjection (CRS
# @detectSQLi/@detectXSS operators) and others/mbedtls (crypto
# helpers) are populated in-tree, and configure is pregenerated, so
# no submodule clone and no autotools rebuild (bun-style cloning is
# unnecessary here). Hadrian-side needs are covered by alex/happy;
# this engine needs only C++17 (gcc), flex/bison output is shipped
# (parser regeneration stays off - no flex/bison in makedepends).
#
# Optional operator libraries missing from Saphira stay off and fail
# visibly only if CRS needs them: ssdeep (fuzzy @inspectFile - no CRS
# requirement) and lua (opt-in CRS plugins only) are absent by design.
# libxml2/curl/pcre2/maxmind/geoip autodetect from makedepends.

pkgname=modsecurity
pkgver=3.0.16
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="ModSecurity v3 web application firewall engine library"
license=Apache-2.0
origin=modsecurity
repo=saphira
url=https://modsecurity.org/
source=https://github.com/owasp-modsecurity/ModSecurity/releases/download/v3.0.16/modsecurity-v3.0.16.tar.gz
sha256=739be3c71b1939f14e91afe1eeae654acbd440da11bd29790458840bc315b4c0

depends="
    curl
    libgeoip
    libmaxminddb
    libxml2
    musl
    pcre2
    yajl
"
makedepends="
    binutils
    curl-dev
    gawk
    gcc
    libgeoip
    libmaxminddb-dev
    libxml2-dev
    make
    pcre2-dev
    pkgconf
    yajl-dev
"
subpackages="$pkgname-dev"

recipe_build()
{
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/modsecurity-v3.0.16.tar.gz"
	echo "$sha256  $RECIPE_DIR/files/modsecurity-v3.0.16.tar.gz" | sha256sum -c -
	cd "$SRC"
	# Flag confidence: --prefix/--with-yajl/--disable-doxygen-doc are
	# certain (configure --help); the rest is default autodetection.
	# libinjection/mbedtls must be present or configure fails here.
	test -d others/libinjection -a -d others/mbedtls ||
		{ echo "ERROR: bundled third-party sources missing" >&2; return 1; }
	./configure --prefix=/usr \
		--with-yajl=/usr \
		--disable-examples \
		--disable-doxygen-doc
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
	# Engine library plus the upstream recommended config and unicode
	# mapping as inert examples (wiring copies them into place).
	test -f "$PKGDEST/usr/lib/libmodsecurity.so.3" ||
		{ echo "ERROR: libmodsecurity.so.3 missing from payload" >&2; return 1; }
	install -D -m0644 "$SRC/modsecurity.conf-recommended" \
		"$PKGDEST/usr/share/doc/modsecurity/modsecurity.conf-recommended"
	install -D -m0644 "$SRC/unicode.mapping" \
		"$PKGDEST/usr/share/doc/modsecurity/unicode.mapping"
}
