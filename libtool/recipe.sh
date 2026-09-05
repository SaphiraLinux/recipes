#!/bin/sh

pkgname=libtool
pkgver=2.5.4
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Generic library support script"
license="LGPL-2.0-or-later GPL-2.0-or-later"
origin=libtool
repo=main
url=https://www.gnu.org/software/libtool/
source=https://ftp.gnu.org/gnu/libtool/libtool-${pkgver}.tar.xz
sha256=f81f5860666b0bc7d84baddefa60d1cb9fa6fceb2398cc3baca6afaa60266675

depends=""

makedepends="
    binutils
    gawk
    gcc
    m4
    make
"

subpackages="libtool-dev libtool-doc"
recipe_build()
{
	# Preserve the proven Saphira v0 libtool build decisions while moving
	# the package into native APK ownership.  The release archive carries a
	# generated configure script, so no autotools macros are needed here;
	# upstream installs its libtool.m4 and ltdl.m4 into the unversioned
	# aclocal directory that repository automake consumers expect.
	./configure \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var
	make
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
}
