#!/bin/sh

pkgname=unzip
pkgver=6.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="List, test and extract ZIP archives"
license=Info-ZIP
origin=unzip
repo=main
url=https://infozip.sourceforge.net/UnZip.html
source=https://downloads.sourceforge.net/infozip/unzip60.tar.gz
sha256=036d96991646d0449ed0aa952e4fbe21b476ce994abc276e49d30e686708bd37

depends="
    bzip2
"
makedepends="
    binutils
    bzip2-dev
    gcc
    make
"
subpackages=""

recipe_build()
{
	make -C "$SRC" -f unix/Makefile unzips \
		prefix=/usr \
		LF2= \
		D_USE_BZ2=-DUSE_BZIP2 \
		L_BZ2=-lbz2 \
		CFLAGS="${CFLAGS-} -DWILD_STOP_AT_DIR -DLARGE_FILE_SUPPORT -DUNICODE_SUPPORT -DUNICODE_WCHAR -DUTF8_MAYBE_NATIVE -DNO_LCHMOD -DDATE_FORMAT=DF_YMD -DUSE_BZIP2 -DNATIVE"
}

recipe_install()
{
	install -d "$PKGDEST/usr/bin" "$PKGDEST/usr/share/man/man1"
	install -m 755 "$SRC/unzip" "$PKGDEST/usr/bin/unzip"
	install -m 644 "$SRC/man/unzip.1" "$PKGDEST/usr/share/man/man1/unzip.1"
}
