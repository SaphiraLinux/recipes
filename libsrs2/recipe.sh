#!/bin/sh

pkgname=libsrs2
pkgver=1.0.18
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Sender Rewriting Scheme library (qmail SRS patch needs it)"
# Dual-licensed at the user's discretion (COPYING in-tree):
# GPL-2.0-only or BSD-3-Clause (LICENSE.GPL-2, LICENSE.BSD).
license="GPL-2.0-only OR BSD-3-Clause"
origin=libsrs2
repo=main
url=https://www.libsrs2.org/
subpackages="
    $pkgname-dev
"
# Upstream publishes through the sagredo mirror (the copy the qmail
# tree's own install notes point at).
source=https://notes.sagredo.eu/files/qmail/tar/libsrs2-1.0.18.tar.gz
sha256=9d1191b705d7587a5886736899001d04168392bbb6ed6345a057ade50943a492

depends=""

makedepends="
    binutils
    gawk
    gcc
    make
"

recipe_build()
{
	./configure 		--prefix=/usr 		--sysconfdir=/etc 		--localstatedir=/var 		--disable-static
	make
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
}
