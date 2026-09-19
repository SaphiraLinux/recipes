#!/bin/sh

pkgname=libev
pkgver=4.33
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="High-performance event loop library (nghttpx/nghttp apps need it)"
license="BSD-2-Clause AND GPL-2.0-or-later"
origin=libev
repo=saphira
url=http://dist.schmorp.de/libev/
source=http://dist.schmorp.de/libev/libev-4.33.tar.gz
sha256=507eb7b8d1015fbec5b935f34ebed15bf346bed04a11ab82b8eee848c4205aea

depends=""

makedepends="
    binutils
    gcc
    make
"

subpackages="libev-dev"

# Dual-licensed BSD/GPL; either satisfies the tree.
recipe_build()
{
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	"$SRC/configure" --prefix=/usr --sysconfdir=/etc --disable-static --localstatedir=/var
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$BUILDDIR" DESTDIR="$PKGDEST" install
	# event.h is libev's libevent-compat shim ("only core events
	# supported"); the real header belongs to libevent-dev, published
	# with consumers. One owner per path, so the shim yields - libev
	# consumers include ev.h, which is untouched.
	rm -f "$PKGDEST/usr/include/event.h"
}
