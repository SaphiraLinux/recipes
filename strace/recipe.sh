#!/bin/sh

pkgname=strace
pkgver=6.17
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='System call tracer'
license='LGPL-2.1-or-later'
origin=strace
repo=saphira
url=https://strace.io/
source=https://github.com/strace/strace/releases/download/v${pkgver}/strace-${pkgver}.tar.xz
sha256=0a7c7bedc7efc076f3242a0310af2ae63c292a36dd4236f079e88a93e98cb9c0

makedepends="gcc make pkgconf"

subpackages="$pkgname-doc"

recipe_build()
{
	cd "$SRC"
	./configure --prefix=/usr --with-libunwind=no --enable-mpers=no \
		--enable-bundled=yes
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
