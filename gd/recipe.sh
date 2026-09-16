#!/bin/sh

# New port (no cports template, no reference recipe): minimal libgd
# image core for the nginx image_filter module. PNG+JPEG only: no
# freetype/fontconfig/xpm/tiff/webp/heif recipes exist yet, and the
# filter needs only raster create/resize/copy. Text support stays out
# until the font stack lands (revisit flags then, bump pkgrel).
# libpng carries its headers in the main package (no -dev split), so
# it is named directly in makedepends/depends_dev.

pkgname=gd
pkgver=2.3.3
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="libgd image library (PNG/JPEG core for nginx image_filter)"
license="libgd"
origin=gd
repo=saphira
url=https://libgd.github.io/
source=https://github.com/libgd/libgd/releases/download/gd-2.3.3/libgd-2.3.3.tar.xz
sha256=3fe822ece20796060af63b7c60acb151e5844204d289da0ce08f8fdf131e5a61

depends="
    libjpeg-turbo
    libpng
    zlib
"

depends_dev="libjpeg-turbo-dev libpng zlib-dev"

makedepends="
    binutils
    cmake
    gcc
    libjpeg-turbo-dev
    libpng
    make
    pkgconf
    zlib-dev
"

subpackages="gd-dev"

recipe_build()
{
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	cmake "$SRC" \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DCMAKE_BUILD_TYPE=Release \
		-DBUILD_TEST=0 \
		-DENABLE_PNG=1 -DENABLE_JPEG=1 \
		-DENABLE_TIFF=0 -DENABLE_XPM=0 -DENABLE_FREETYPE=0 \
		-DENABLE_FONTCONFIG=0 -DENABLE_WEBP=0 -DENABLE_HEIF=0 \
		-DENABLE_AVIF=0 -DENABLE_RAQM=0
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$BUILDDIR" DESTDIR="$PKGDEST" install
}
