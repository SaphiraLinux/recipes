#!/bin/sh

pkgname=lsof
pkgver=4.99.6
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Lists open files and processes using them'
license='lsof'
origin=lsof
repo=saphira
url=https://github.com/lsof-org/lsof
source=https://github.com/lsof-org/lsof/releases/download/${pkgver}/lsof-${pkgver}.tar.gz
sha256=6081dedf841cd61f8a022ff7cbe04ed78918a47dea3c39528c8571474167aa0f

makedepends="gcc make pkgconf"

subpackages="$pkgname-doc"

recipe_build()
{
	cd "$SRC"
	./configure --prefix=/usr
	touch lsof.man
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
