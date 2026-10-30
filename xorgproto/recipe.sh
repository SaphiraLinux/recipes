#!/bin/sh

pkgname=xorgproto
pkgver=2024.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="X11 protocol headers (unified xorgproto, X client stack base)"
license="MIT"
origin=xorgproto
repo=main
url=https://www.x.org/
vendor=https://www.x.org/releases/individual/proto/xorgproto-2024.1.tar.xz
sha256=372225fd40815b8423547f5d890c5debc72e88b91088fbfb13158c20495ccb59

# Headers only, no library, no daemon. Ships the unified protocol
# headers (X11/, X11/extensions/, GL/) plus one .pc per merged proto
# (xproto, xextproto, ...). No -dev split: like freetype/libpng,
# headers live in main and consumers reference the main package.
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
	echo "$sha256  $RECIPE_DIR/files/xorgproto-2024.1.tar.xz" | sha256sum -c -
	rm -rf "$BUILDDIR" && mkdir -p "$BUILDDIR"
	tar --no-same-owner -xf "$RECIPE_DIR/files/xorgproto-2024.1.tar.xz" \
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
	# Payload proof: the core header plus the compat .pc files the
	# X client stack resolves (xproto, xextproto).
	for p in usr/include/X11/X.h \
		usr/share/pkgconfig/xproto.pc \
		usr/share/pkgconfig/xextproto.pc; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: xorgproto payload is missing $p" >&2
			return 1
		}
	done
}
