#!/bin/sh

pkgname=libXrender
pkgver=0.9.13
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="X rendering extension library (libXrender, unblocks JDK java2d)"
license="MIT"
origin=libXrender
repo=main
url=https://www.x.org/
vendor=https://www.x.org/releases/individual/lib/libXrender-0.9.13.tar.xz
sha256=3fe88c609df6782e1e7af2e4de36b2563d70cd70ff7dcb1cda561ad64912bb64

# Security refresh 0.9.13 (Oct 2026 X client advisory fixes).
# Runtime edges are DT_NEEDED providers (libX11; xorgproto is
# headers-only). The JDK's shared java2d includes Xrender.h, so
# libXrender-dev unblocks the headless build next.
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
	echo "$sha256  $RECIPE_DIR/files/libXrender-0.9.13.tar.xz" | sha256sum -c -
	rm -rf "$BUILDDIR" && mkdir -p "$BUILDDIR"
	tar --no-same-owner -xf "$RECIPE_DIR/files/libXrender-0.9.13.tar.xz" \
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
	# split) the JDK includes.
	for p in usr/lib/libXrender.so \
		usr/include/X11/extensions/Xrender.h; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: libXrender payload is missing $p" >&2
			return 1
		}
	done
}
