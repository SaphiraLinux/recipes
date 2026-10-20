#!/bin/sh

pkgname=freetype
pkgver=2.15.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="FreeType font rasterisation library (headless text rendering)"
license='FTL'
origin=freetype
repo=saphira
url=https://freetype.org/
source=https://download.savannah.gnu.org/releases/freetype/freetype-2.15.0.tar.xz
sha256=93cd47eb719c325107f2d3cf087d06299e944c3b48a40b55537302304dea1dd5

depends="
    zlib
    libpng
    bzip2
"

makedepends="
    binutils
    gcc
    make
    pkgconf
    zlib-dev
    bzip2-dev
"

# Development files ship in the main package; no -dev split
# (libpng idiom). No harfbuzz in the universe: freetype disables
# the HarfBuzz shaper itself when it is absent (documented
# upstream behaviour, not a feature cut).
recipe_build()
{
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	"$SRC/configure" --prefix=/usr --sysconfdir=/etc --disable-static \
		--localstatedir=/var --with-zlib=yes --with-png=yes \
		--with-bzip2=yes --with-harfbuzz=no
	make
}

recipe_install()
{
	make -C "$BUILDDIR" DESTDIR="$PKGDEST" install
}
