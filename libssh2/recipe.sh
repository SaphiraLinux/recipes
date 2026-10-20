#!/bin/sh

# libssh2: SSH2 protocol library (OpenSSL backend).

pkgname=libssh2
pkgver=1.11.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="SSH2 protocol library (OpenSSL backend)"
license="BSD-3-Clause"
origin=libssh2
repo=saphira
url=https://libssh2.org/
source=https://libssh2.org/download/libssh2-${pkgver}.tar.gz
sha256=d9ec76cbe34db98eec3539fe2c899d26b0c837cb3eb466a56b0f109cabf658f7

# OpenSSL backend is explicit (not autodetected); zlib compression
# is core SSH functionality, not an optional extra.
makedepends="
    binutils
    gcc
    make
    openssl-dev
    pkgconf
    zlib-dev
"

subpackages="$pkgname-dev $pkgname-doc"

recipe_build()
{
	./configure \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--libdir=/usr/lib \
		--with-openssl \
		--with-libz
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
	install -D -m 0644 "$SRC/COPYING" \
		"$PKGDEST/usr/share/licenses/libssh2/COPYING"
	# .a/.pc/headers to -dev, man pages to -doc via the fixed split
	# predicates; the versioned .so stays in main.
	for p in usr/lib/libssh2.so usr/include/libssh2.h; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: libssh2 payload is missing $p" >&2
			return 1
		}
	done
}
