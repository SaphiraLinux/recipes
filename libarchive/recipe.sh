#!/bin/sh

pkgname=libarchive
pkgver=3.8.8
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Multi-format archive and compression library"
license="BSD-2-Clause"
origin=libarchive
repo=main
url=https://www.libarchive.org/
source=https://github.com/libarchive/libarchive/releases/download/v3.8.8/libarchive-3.8.8.tar.gz
sha256=038918ea315cdd446cc63acfe880d6011832bbe1711c887de5de5441b306c190

depends="
    acl
    attr
    bzip2
    libxml2
    lz4
    openssl
    xz
    zstd
"

subpackages="$pkgname-dev $pkgname-doc"
makedepends="
    acl-dev
    attr-dev
    binutils
    bzip2-dev
    gcc
    libxml2
    lz4-dev
    make
    openssl-dev
    xz-dev
    zstd-dev
"

# xml2 (not expat) for XML; openssl (not nettle) is the crypto backend.
recipe_build()
{
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	"$SRC/configure" --prefix=/usr \
		--enable-acl --enable-xattr --with-openssl \
		--with-lz4 --with-bz2lib --with-lzma --with-zstd \
		--with-xml2 --without-expat --without-nettle \
		--disable-static --disable-rpath
	make
}

recipe_install()
{
	make -C "$BUILDDIR" DESTDIR="$PKGDEST" install
}
