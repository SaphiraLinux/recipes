#!/bin/sh

pkgname=less
pkgver=704
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Terminal pager'
license='GPL-3.0-or-later OR BSD-2-Clause'
origin=less
repo=saphira
url=https://www.greenwoodsoftware.com/less/
source=https://www.greenwoodsoftware.com/less/less-${pkgver}.tar.gz
sha256=20a0b0a2bb2525fa53c7eee9beb854b4c9cf172eabb209af7020743547bfe9fb

depends="ncurses"
makedepends="gcc make pkgconf ncurses-dev"

subpackages="$pkgname-doc"

recipe_build()
{
	cd "$SRC"
	./configure --prefix=/usr --with-regex=posix
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
