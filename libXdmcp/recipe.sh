#!/bin/sh

pkgname=libXdmcp
pkgver=1.1.5
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="X Display Manager Control Protocol library (libXdmcp, X client stack)"
license="MIT"
origin=libXdmcp
repo=main
url=https://www.x.org/
vendor=https://www.x.org/releases/individual/lib/libXdmcp-1.1.5.tar.xz
sha256=d8a5222828c3adab70adf69a5583f1d32eb5ece04304f7f8392b6a353aa2228c

depends="
"

makedepends="
    binutils
    gcc
    make
    pkgconf
    xorgproto
"

subpackages="
    $pkgname-dev
"

# XDM-AUTH/ wrap codec for X connections. Needs only the protocol
# headers at build; nothing at runtime (xorgproto is headers-only).
# Release tarball ships generated configure.
recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/libXdmcp-1.1.5.tar.xz" | sha256sum -c -
	rm -rf "$BUILDDIR" && mkdir -p "$BUILDDIR"
	tar --no-same-owner -xf "$RECIPE_DIR/files/libXdmcp-1.1.5.tar.xz" \
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
	# split) libxcb consumes.
	for p in usr/lib/libXdmcp.so \
		usr/include/X11/Xdmcp.h; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: libXdmcp payload is missing $p" >&2
			return 1
		}
	done
}
