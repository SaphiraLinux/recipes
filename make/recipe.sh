#!/bin/sh

pkgname=make
pkgver=4.4.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="GNU tool for controlling program generation"
license="GPL-3.0-or-later"
origin=make
repo=main
url=https://www.gnu.org/software/make/
source=https://ftp.gnu.org/gnu/make/make-${pkgver}.tar.gz
sha256=dd16fb1d67bfab79a72f5e8390735c49e3e8e70b4945a15ab1f81ddb78658fb3

depends=""
makedepends="gcc binutils gawk"

recipe_build()
{
	# Preserve the known-working Saphira C23 compatibility decision from the
	# historical recipe while bootstrapping with GCC 16.
	CFLAGS="${CFLAGS-} -std=gnu17" ./configure \
		--prefix=/usr \
		--disable-dependency-tracking \
		--without-guile
	# GNU make's bootstrap script builds the first make without requiring
	# an already-installed make.  This is the stage-0 package bootstrap.
	./build.sh
}

recipe_install()
{
	install -d "$PKGDEST/usr/bin" "$PKGDEST/usr/share/man/man1"
	install -m 755 make "$PKGDEST/usr/bin/make"
	install -m 644 doc/make.1 "$PKGDEST/usr/share/man/man1/make.1"
}
