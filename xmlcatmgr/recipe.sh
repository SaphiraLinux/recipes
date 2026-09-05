#!/bin/sh

pkgname=xmlcatmgr
pkgver=2.2
pkgrel=4
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="XML and SGML catalog manager"
license=BSD-3-Clause
origin=xmlcatmgr
repo=main
url=https://sourceforge.net/projects/xmlcatmgr/
source=https://downloads.sourceforge.net/xmlcatmgr/xmlcatmgr-${pkgver}.tar.gz
sha256=ea1142b6aef40fbd624fc3e2130cf10cf081b5fa88e5229c92b8f515779d6fdc

depends=""
makedepends="
    automake
    libtool
"
subpackages=""

recipe_build()
{
	cd "$SRC"
	./configure --prefix=/usr --mandir=/usr/share/man
	make
}

recipe_install()
{
	DESTDIR="$PKGDEST" make -C "$SRC" install
}
