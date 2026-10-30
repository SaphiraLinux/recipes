#!/bin/sh

pkgname=libXext
pkgver=1.3.7
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="X11 extension library (libXext, X client stack)"
license="MIT"
origin=libXext
repo=main
url=https://www.x.org/
vendor=https://www.x.org/releases/individual/lib/libXext-1.3.7.tar.xz
sha256=6c643c7035cdacf67afd68f25d01b90ef889d546c9fcd7c0adf7c2cf91e3a32d

# Runtime edges are DT_NEEDED providers (libX11; xorgproto is
# headers-only). Links libXaw? No: plain X extension wire codec.
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
	echo "$sha256  $RECIPE_DIR/files/libXext-1.3.7.tar.xz" | sha256sum -c -
	rm -rf "$BUILDDIR" && mkdir -p "$BUILDDIR"
	tar --no-same-owner -xf "$RECIPE_DIR/files/libXext-1.3.7.tar.xz" \
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
	for p in usr/lib/libXext.so \
		usr/include/X11/extensions/Xext.h; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: libXext payload is missing $p" >&2
			return 1
		}
	done
}
