#!/bin/sh

pkgname=dialog
pkgver=1.3.20251001
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Script-friendly tool for building TUI dialogs and menus from shell"
license="LGPL-2.1-or-later"
origin=dialog
repo=saphira
url=https://invisible-island.net/dialog/
source=https://invisible-island.net/archives/dialog/dialog-1.3-20251001.tgz
sha256=bee47347a983312facc4dbcccd7fcc86608d684e1f119d9049c4692213db96c3

makedepends="
    binutils
    gcc
    gettext-dev
    make
    ncurses-dev
"

recipe_build()
{
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	"$SRC/configure" --prefix=/usr --with-ncursesw --enable-nls
	make
}

recipe_install()
{
	make -C "$BUILDDIR" DESTDIR="$PKGDEST" install
}
