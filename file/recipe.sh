#!/bin/sh

pkgname=file
pkgver=5.48
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='File type identification utility and libmagic'
license='BSD-2-Clause'
origin=file
repo=saphira
url=https://www.darwinsys.com/file/

file_sha256='45672fec165cb4cc1358a2d76b5d57d22876dcb97ab169427ac385cbe1d5597a'

depends="
    bzip2
    xz
    zlib
    zstd
"

makedepends="
    bzip2-dev
    gcc
    make
    xz-dev
    zlib-dev
    zstd-dev
    libseccomp-dev
"

subpackages="
    $pkgname-dev
    $pkgname-doc
"

recipe_build()
{
        echo "$file_sha256  $RECIPE_DIR/files/file-${pkgver}.tar.gz" |
                sha256sum -c -
        tar --no-same-owner \
                -C "$SRC" \
                --strip-components=1 \
                -xf "$RECIPE_DIR/files/file-${pkgver}.tar.gz"

        mkdir -p "$BUILDDIR"
        cd "$BUILDDIR"

        "$SRC/configure" \
                --prefix=/usr \
                --libdir=/usr/lib \
                --enable-static

        make -j${JOBS:-$(nproc)}
}

recipe_install()
{
        cd "$BUILDDIR"
        DESTDIR="$PKGDEST" make install

        find "$PKGDEST" -name '*.la' -delete
}
