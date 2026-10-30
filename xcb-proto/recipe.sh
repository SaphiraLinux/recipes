#!/bin/sh

pkgname=xcb-proto
pkgver=1.17.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="X C Binding protocol descriptions and generator (libxcb build input)"
license="MIT"
origin=xcb-proto
repo=main
url=https://www.x.org/
vendor=https://www.x.org/releases/individual/proto/xcb-proto-1.17.0.tar.xz
sha256=2c1bacd2110f4799f74de6ebb714b94cf6f80fb112316b1219480fd22562148c

# Build-time only: protocol XML plus the xcbgen generator libxcb
# runs at ITS build. Nothing links it at runtime, so no consumer
# carries a runtime edge on this package. No -dev split.
depends="
"

makedepends="
    binutils
    gcc
    make
    pkgconf
    python3
"

# Release tarball ships generated configure (verified in-archive).
# python3 byte-compiles the generator at build time.
recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/xcb-proto-1.17.0.tar.xz" | sha256sum -c -
	rm -rf "$BUILDDIR" && mkdir -p "$BUILDDIR"
	tar --no-same-owner -xf "$RECIPE_DIR/files/xcb-proto-1.17.0.tar.xz" \
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
	# Payload proof: the .pc libxcb's configure resolves plus the
	# protocol XML the generator consumes.
	for p in usr/share/pkgconfig/xcb-proto.pc \
		usr/share/xcb/xproto.xml; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: xcb-proto payload is missing $p" >&2
			return 1
		}
	done
}
