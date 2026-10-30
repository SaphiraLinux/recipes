#!/bin/sh

pkgname=libXtst
pkgver=1.2.6
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="X11 testing extension library (libXtst, X client stack)"
license="MIT"
origin=libXtst
repo=main
url=https://www.x.org/
vendor=https://www.x.org/releases/individual/lib/libXtst-1.2.6.tar.xz
sha256=f94f0b37c07d80d877f3eda2c2405cc7e62aa9842f6310354aa349e3d66a4fe5

# Security refresh 1.2.6 (Oct 2026 X client advisory fixes).
# Runtime edges are DT_NEEDED providers (RUNTIME gate verifies the
# closure and fails loudly otherwise).
depends="
    libX11
    libXext
    libXi
"

makedepends="
    binutils
    gcc
    libX11-dev
    libXau-dev
    libXdmcp-dev
    libXext-dev
    libXfixes-dev
    libXi-dev
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
	echo "$sha256  $RECIPE_DIR/files/libXtst-1.2.6.tar.xz" | sha256sum -c -
	rm -rf "$BUILDDIR" && mkdir -p "$BUILDDIR"
	tar --no-same-owner -xf "$RECIPE_DIR/files/libXtst-1.2.6.tar.xz" \
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
	for p in usr/lib/libXtst.so \
		usr/include/X11/extensions/XTest.h; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: libXtst payload is missing $p" >&2
			return 1
		}
	done
}
