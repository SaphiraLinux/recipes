#!/bin/sh

pkgname=libcap
pkgver=2.78
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="POSIX.1e capabilities suite"
license="GPL-2.0-only"
origin=libcap
repo=main
url=https://sites.google.com/site/fullycapable/
source=https://www.kernel.org/pub/linux/libs/security/linux-privs/libcap2/libcap-${pkgver}.tar.xz
sha256=0d621e562fd932ccf67b9660fb018e468a683d7b827541df27813228c996bb11

depends=""

makedepends="
    binutils
    gcc
    saphira-kernel-headers=7.1.5
    make
    perl
    pkgconf
"

subpackages="
    $pkgname-dev
    $pkgname-doc
"

recipe_build()
{
	make -C "$SRC" GOLANG=no
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" prefix=/usr lib=lib \
		PKGCONFIGDIR=/usr/lib/pkgconfig \
		SBINDIR=/usr/bin LIBDIR=/usr/lib exec_prefix=/usr \
		GOLANG=no RAISE_SETFCAP=no install
}
