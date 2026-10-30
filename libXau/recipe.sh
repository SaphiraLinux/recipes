#!/bin/sh

pkgname=libXau
pkgver=1.0.12
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="X11 authorization library (libXau, X client stack)"
license="MIT"
origin=libXau
repo=main
url=https://www.x.org/
vendor=https://www.x.org/releases/individual/lib/libXau-1.0.12.tar.xz
sha256=74d0e4dfa3d39ad8939e99bda37f5967aba528211076828464d2777d477fc0fb

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

# Authorization record codec for X connections. Needs only the
# protocol headers at build; nothing at runtime (xorgproto is
# headers-only). Release tarball ships generated configure.
recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/libXau-1.0.12.tar.xz" | sha256sum -c -
	rm -rf "$BUILDDIR" && mkdir -p "$BUILDDIR"
	tar --no-same-owner -xf "$RECIPE_DIR/files/libXau-1.0.12.tar.xz" \
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
	for p in usr/lib/libXau.so \
		usr/include/X11/Xauth.h; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: libXau payload is missing $p" >&2
			return 1
		}
	done
}
