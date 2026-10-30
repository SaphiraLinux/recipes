#!/bin/sh

pkgname=libXi
pkgver=1.8.4
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="X11 input extension library (libXi, X client stack)"
license="MIT"
origin=libXi
repo=main
url=https://www.x.org/
vendor=https://www.x.org/releases/individual/lib/libXi-1.8.4.tar.xz
sha256=ddd6057b89a91903bc2f884d55c8467440906945e482c36547260dff28661afc

# Security refresh 1.8.4 (Oct 2026 X client advisory fixes).
# Runtime edges are DT_NEEDED providers (RUNTIME gate verifies the
# closure and fails loudly otherwise).
depends="
    libX11
    libXext
    libXfixes
"

makedepends="
    binutils
    gcc
    libX11-dev
    libXau-dev
    libXdmcp-dev
    libXext-dev
    libXfixes-dev
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
	echo "$sha256  $RECIPE_DIR/files/libXi-1.8.4.tar.xz" | sha256sum -c -
	rm -rf "$BUILDDIR" && mkdir -p "$BUILDDIR"
	tar --no-same-owner -xf "$RECIPE_DIR/files/libXi-1.8.4.tar.xz" \
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
	for p in usr/lib/libXi.so \
		usr/include/X11/extensions/XInput2.h; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: libXi payload is missing $p" >&2
			return 1
		}
	done
}
