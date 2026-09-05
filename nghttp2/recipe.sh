#!/bin/sh

pkgname=nghttp2
pkgver=1.70.0
pkgrel=1
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

makedepends="
    binutils
    gcc
    make
"

# Proven v0 scope: the HTTP/2 library (libnghttp2) that bind/curl
# consume. The nghttpx/nghttp/nghttpd applications additionally need
# c-ares and libev, which are not in the current native universe
# (BLOCKED_BY_c-ares, BLOCKED_BY_libev) - porting those would extend
# this unit's feature set and is a deliberate follow-up, not a silent
# capability removal.
recipe_build()
{
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	"$SRC/configure" --prefix=/usr --enable-lib-only --disable-static
	make
}

recipe_install()
{
	make -C "$BUILDDIR" DESTDIR="$PKGDEST" install
}
