#!/bin/sh

pkgname=m4
pkgver=1.4.19
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="GNU macro processor"
license="GPL-3.0-or-later"
origin=m4
repo=main
url=https://www.gnu.org/software/m4/
source=https://ftp.gnu.org/gnu/m4/m4-${pkgver}.tar.xz
sha256=63aede5c6d33b6d9b13511cd0be2cac046f2e70fd0a07aa9573a04a82783af96

depends=""

makedepends="
    binutils
    gawk
    gcc
    make
"

subpackages="m4-doc"
recipe_build()
{
	# Preserve the proven Saphira v0 decision: -std=gnu17 keeps the
	# gnulib-era sources building against modern GCC defaults
	# (AKADATA_POLICY_EXCEPTION=m4-gnu17-compat).
	CFLAGS="${CFLAGS-} -std=gnu17" ./configure \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var
	make
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
}
