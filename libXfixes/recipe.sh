#!/bin/sh

pkgname=libXfixes
pkgver=6.0.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="X11 fixes extension library (libXfixes, X client stack)"
license="MIT"
origin=libXfixes
repo=main
url=https://www.x.org/
vendor=https://www.x.org/releases/individual/lib/libXfixes-6.0.2.tar.xz
sha256=39f115d72d9c5f8111e4684164d3d68cc1fd21f9b27ff2401b08fddfc0f409ba

# Runtime edges are DT_NEEDED providers (libX11; xorgproto is
# headers-only). Required peer of libXi/libXtst.
depends="
    libX11
"

makedepends="
    binutils
    gcc
    libX11-dev
    libXau-dev
    libXdmcp-dev
    libxcb-dev
    make
    pkgconf
    xorgproto
"

subpackages="
    $pkgname-dev
"

# Release tarball ships generated configure (verified in-archive);
# no build options need decisions (all defaults).
recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/libXfixes-6.0.2.tar.xz" | sha256sum -c -
	rm -rf "$BUILDDIR" && mkdir -p "$BUILDDIR"
	tar --no-same-owner -xf "$RECIPE_DIR/files/libXfixes-6.0.2.tar.xz" \
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
	# Payload proof: runtime object plus the header (auto -dev
	# split) consumers include.
	for p in usr/lib/libXfixes.so \
		usr/include/X11/extensions/Xfixes.h; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: libXfixes payload is missing $p" >&2
			return 1
		}
	done
}
