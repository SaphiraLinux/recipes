#!/bin/sh

pkgname=imagemagick
pkgver=7.1.2-29
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Image editing and conversion suite"
license="ImageMagick"
origin=imagemagick
repo=saphira
url=https://imagemagick.org/
source=https://github.com/ImageMagick/ImageMagick/releases/download/7.1.2-29/ImageMagick-7.1.2-29.tar.xz
sha256=4b131411aa77b051908ea35df65ca2c52dbe04b48c3ef6b06f35c1bb595b212f

depends="
    libjpeg-turbo
    libpng
    libwebp
    libxml2
    zlib
"

makedepends="
    binutils
    gcc
    libjpeg-turbo-dev
    libpng
    libwebp
    libxml2
    make
    perl
    pkgconf
    zlib-dev
"

recipe_build()
{
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	# jpeg/png/webp/xml/perl/Magick++ enabled (deps exist); freetype/tiff/
	# x/lcms2/openjp2 stay off until their recipes land (BLOCKED_BY_*).
	"$SRC/configure" --prefix=/usr --disable-static \
		--with-modules --with-perl --with-magick-plus-plus=yes \
		--with-jpeg=yes --with-png=yes --with-webp=yes --with-xml=yes \
		--without-freetype --without-tiff --without-x \
		--without-lcms --without-openjp2
	make
}

recipe_install()
{
	make -C "$BUILDDIR" DESTDIR="$PKGDEST" install
}
