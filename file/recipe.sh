#!/bin/sh

pkgname=file
pkgver=5.48
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='File type identification utility and libmagic'
license='BSD-2-Clause'
origin=file
repo=saphira
url=https://www.darwinsys.com/file/

file_sha256='ed14656883b23a364b4057c05595d93252da9bc473d30106519519d0da141283'

depends="
    bzip2
    libseccomp
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
                --sysconfdir=/etc \
                --localstatedir=/var \
                --libdir=/usr/lib \
                --disable-static

        make -j${JOBS:-$(nproc)}
}

recipe_install()
{
        cd "$BUILDDIR"
        DESTDIR="$PKGDEST" make install

        find "$PKGDEST" -name '*.la' -delete
        # FHS non-usrmerged: libmagic serves only /usr/bin/file, so the
        # runtime stays in /usr/lib. Egg carries unowned stage1 fossils
        # in /lib (/lib/libmagic.so*); the package must never stage /lib.
        if [ -e "$PKGDEST/lib" ]; then
                echo "ERROR: file must not stage /lib (runtime is /usr/lib)" >&2
                return 1
        fi
        # Stage1-leak guard (2026-10-19 fossil incident): a clean native
        # build must never embed /saphirabuild stage paths. The stripped
        # native payload has zero hits; fail closed if one ever reappears.
        if grep -rqF '/saphirabuild/' "$PKGDEST"; then
                echo "ERROR: staged payload leaks /saphirabuild stage path" >&2
                return 1
        fi
}
