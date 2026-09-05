#!/bin/sh

pkgname=tree
pkgver=2.3.2
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Recursive directory listing tool'
license='GPL-2.0-or-later'
origin=tree
repo=saphira
url=http://mama.indstate.edu/users/ice/tree/
source=https://github.com/Old-Man-Programmer/tree/archive/refs/tags/${pkgver}.tar.gz
sha256=22cf32e84e3eb508d97a9e991c2c3cc006b9dcf4afed201d96311c5c57d08fcf

makedepends="gcc make"

subpackages="$pkgname-doc"

recipe_build()
{
	cd "$SRC"
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$SRC" PREFIX=/usr MANDIR=/usr/share/man DESTDIR="$PKGDEST" install
}
