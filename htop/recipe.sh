#!/bin/sh

pkgname=htop
pkgver=3.5.2
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Interactive process viewer'
license='GPL-2.0-or-later'
origin=htop
repo=saphira
url=https://htop.dev/
source=https://github.com/htop-dev/htop/releases/download/${pkgver}/htop-${pkgver}.tar.xz
sha256=225128e697c4a8c8a878fd0078c965ff8bd5fb24913bfc8473b8edbd50f843f8

depends="ncurses libcap libnl"
makedepends="gcc make pkgconf ncurses-dev libcap-dev libnl-dev"

subpackages="$pkgname-doc"

recipe_build()
{
	cd "$SRC"
	./configure --prefix=/usr \
		--enable-capabilities --enable-delayacct \
		--enable-unicode --disable-sensors
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
