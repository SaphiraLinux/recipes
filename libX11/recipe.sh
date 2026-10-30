#!/bin/sh

pkgname=libX11
pkgver=1.8.14
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="X11 client library (libX11, X client stack; headers unblock the JDK build)"
license="MIT"
origin=libX11
repo=main
url=https://www.x.org/
vendor=https://www.x.org/releases/individual/lib/libX11-1.8.14.tar.xz
sha256=bbc78c46217174655c2b32b138ad119f3ac15f50808b4d0b3a2677a4b1afc950

# Security refresh 1.8.14 (Oct 2026 X client advisory fixes).
# Runtime edges are DT_NEEDED providers (libxcb; xorgproto and
# xtrans are headers-only). The JDK consumes headers only (headless
# libawt links no X, proven in Awt2dLibraries.gmk); the seed's
# libawt_xawt.so is what will link libX11 at its runtime.
depends="
    libxcb
"

makedepends="
    binutils
    gcc
    libXau-dev
    libXdmcp-dev
    libxcb-dev
    make
    pkgconf
    xorgproto
    xtrans
"

subpackages="
    $pkgname-dev
"

# xcb support stays default-on (required peer: libxcb-dev).
# Specs skip gracefully without xmlto/fop (developer docs, not a
# shipped capability); launchd is macOS-only (auto-off on Linux).
# i18n/xlocale/xkb/compose-cache stay upstream-default (locale data
# ships, determines no extra provider). Release tarball ships
# generated configure.
recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/libX11-1.8.14.tar.xz" | sha256sum -c -
	rm -rf "$BUILDDIR" && mkdir -p "$BUILDDIR"
	tar --no-same-owner -xf "$RECIPE_DIR/files/libX11-1.8.14.tar.xz" \
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
	# Payload proof: runtime object plus the header the JDK's
	# shared java2d code includes (via libX11-dev).
	for p in usr/lib/libX11.so \
		usr/include/X11/Xlib.h; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: libX11 payload is missing $p" >&2
			return 1
		}
	done
}
