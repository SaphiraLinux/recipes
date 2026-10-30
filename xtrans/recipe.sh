#!/bin/sh

pkgname=xtrans
pkgver=1.6.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="X transport abstraction headers (X client stack build input)"
license="MIT"
origin=xtrans
repo=main
url=https://www.x.org/
vendor=https://www.x.org/releases/individual/lib/xtrans-1.6.0.tar.xz
sha256=faafea166bf2451a173d9d593352940ec6404145c5d1da5c213423ce4d359e92

# Transport headers + makefile fragments only: no library, no
# daemon. Consumers (libX11) reference the main package, like
# xorgproto. No -dev split.
depends="
"

makedepends="
    binutils
    gcc
    make
    pkgconf
"

# Release tarball ships generated configure (verified in-archive).
recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/xtrans-1.6.0.tar.xz" | sha256sum -c -
	rm -rf "$BUILDDIR" && mkdir -p "$BUILDDIR"
	tar --no-same-owner -xf "$RECIPE_DIR/files/xtrans-1.6.0.tar.xz" \
		-C "$BUILDDIR" --strip-components=1
	cd "$BUILDDIR"
	# layout baseline: --prefix=/usr --sysconfdir=/etc
	# --localstatedir=/var (explicit, never inherited).
	./configure \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var
	make
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
	# Payload proof: the transport headers plus the .pc libX11
	# resolves at build time.
	for p in usr/include/X11/Xtrans/Xtrans.h \
		usr/share/pkgconfig/xtrans.pc; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: xtrans payload is missing $p" >&2
			return 1
		}
	done
}
