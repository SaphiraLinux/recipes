#!/bin/sh

pkgname=libuv
pkgver=1.51.0
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Asynchronous I/O library'
license='MIT'
origin=libuv
repo=saphira
url=https://libuv.org/
source=https://dist.libuv.org/dist/v${pkgver}/libuv-v${pkgver}.tar.gz
sha256=5f0557b90b1106de71951a3c3931de5e0430d78da1d9a10287ebc7a3f78ef8eb

makedepends="gcc make pkgconf autoconf automake libtool"

subpackages="$pkgname-dev"

recipe_build()
{
	cd "$SRC"
	./autogen.sh
	./configure --prefix=/usr --disable-static
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
