#!/bin/sh

pkgname=libmaxminddb
pkgver=1.12.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='C library for the MaxMind DB file format (GeoIP2)'
license='Apache-2.0'
origin=libmaxminddb
repo=saphira
url=https://github.com/maxmind/libmaxminddb
source=https://github.com/maxmind/libmaxminddb/releases/download/${pkgver}/libmaxminddb-${pkgver}.tar.gz
sha256=1bfbf8efba3ed6462e04e225906ad5ce5fe958aa3d626a1235b2a2253d600743

depends=""
makedepends="gcc make"

subpackages="$pkgname-dev $pkgname-doc"

recipe_build()
{
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	../source/configure --prefix=/usr --disable-static --disable-tests
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$BUILDDIR" DESTDIR="$PKGDEST" install
	find "$PKGDEST" -name '*.la' -delete
	test -e "$PKGDEST/usr/lib/libmaxminddb.so"
}
