#!/bin/sh

pkgname=automake
pkgver=1.18.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Tool for generating GNU standards-compliant Makefiles"
license="GPL-2.0-or-later"
origin=automake
repo=main
url=https://www.gnu.org/software/automake/
source=https://ftp.gnu.org/gnu/automake/automake-${pkgver}.tar.gz
sha256=63e585246d0fc8772dffdee0724f2f988146d1a3f1c756a3dc5cfbefa3c01915

depends="
    perl
"

makedepends="
    autoconf
    gcc
    make
    perl
"

recipe_build()
{
	# Preserve the proven Saphira v0 automake build decisions while moving
	# the package into native APK ownership.
	./configure \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var
	make
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
	# aclocal aborts when the unversioned macro directory is absent, and no
	# repository package currently provides it; upstream automake itself
	# installs only the versioned aclocal-${pkgver} tree.
	install -d "$PKGDEST/usr/share/aclocal"
}
