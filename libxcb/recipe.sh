#!/bin/sh

pkgname=libxcb
pkgver=1.17.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="X C Binding client library (libxcb, X client stack)"
license="MIT"
origin=libxcb
repo=main
url=https://www.x.org/
vendor=https://www.x.org/releases/individual/lib/libxcb-1.17.0.tar.xz
sha256=599ebf9996710fea71622e6e184f3a8ad5b43d0e5fa8c4e407123c88a59a6d55

# Runtime edges are DT_NEEDED providers (libXau, libXdmcp);
# xcb-proto is build-time only (generator) and correctly absent.
depends="
    libXau
    libXdmcp
"

makedepends="
    binutils
    gcc
    libXau-dev
    libXdmcp-dev
    make
    pkgconf
    python3
    xcb-proto
    xorgproto
"

subpackages="
    $pkgname-dev
"

# Server-side support stays default-off (experimental upstream).
# doxygen/xsltproc are absent from the universe, so API docs and
# man pages skip gracefully (upstream probes, no hard requirement);
# developer specs are not a shipped capability. pthread comes from
# musl itself (pthread-stubs is for non-Linux only, verified in the
# macro). Release tarball ships generated configure.
recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/libxcb-1.17.0.tar.xz" | sha256sum -c -
	rm -rf "$BUILDDIR" && mkdir -p "$BUILDDIR"
	tar --no-same-owner -xf "$RECIPE_DIR/files/libxcb-1.17.0.tar.xz" \
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
	# split) libX11 consumes.
	for p in usr/lib/libxcb.so \
		usr/include/xcb/xcb.h; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: libxcb payload is missing $p" >&2
			return 1
		}
	done
}
