#!/bin/sh

pkgname=nghttp2
pkgver=1.70.0
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="HTTP/2 C library (nghttp2) and tools"
license="MIT"
origin=nghttp2
repo=saphira
url=https://nghttp2.org/
# Upstream moved from ngtcp2/nghttp2 to nghttp2/nghttp2; GitHub-generated
# tag archives are broken upstream - use the signed versioned release
# tarball, verified against upstream checksums.txt.
source=https://github.com/nghttp2/nghttp2/releases/download/v1.70.0/nghttp2-1.70.0.tar.gz
sha256=aa317e2cf9dca6afa0aed68f8fad6ff303ec6982e25a78c75c0b65e2b9b3ded5

depends="
    c-ares
    libev
    openssl
    zlib
"

makedepends="
    binutils
    c-ares-dev
    gcc
    libev-dev
    make
    openssl-dev
    pkgconf
    zlib-dev
"

# Full scope: the HTTP/2 library (libnghttp2) plus the nghttpx/nghttp/
# nghttpd/h2load applications. The apps need c-ares + libev, which were
# absent from the native universe at r1 (BLOCKED_BY_c-ares,
# BLOCKED_BY_libev, lib-only build) - both packaged since, so r2 turns
# the applications on explicitly (configure fails closed if their deps
# ever go missing again instead of silently dropping them).
recipe_build()
{
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	"$SRC/configure" --prefix=/usr --enable-app --disable-static
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$BUILDDIR" DESTDIR="$PKGDEST" install
}
