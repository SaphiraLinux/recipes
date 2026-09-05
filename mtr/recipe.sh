#!/bin/sh

pkgname=mtr
pkgver=0.96
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Network diagnostic tool combining traceroute and ping"
license="GPL-2.0-or-later"
origin=mtr
repo=saphira
url=https://www.bitwizard.nl/mtr/
source=https://www.bitwizard.nl/mtr/files/mtr-0.96.tar.gz
sha256=ffd19a9f8d5f616c1ea2f0da9fbf9d1239bcecdf5a68912e831966d20929037a

makedepends="
    binutils
    gcc
    make
    ncurses-dev
"

# --without-gtk: no GTK recipe in the native universe; curses UI only.
recipe_build()
{
	cd "$SRC"
	./configure --prefix=/usr --without-gtk
	make
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
