#!/bin/sh
pkgname=lz4
pkgver=1.10.0
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Extremely fast compression algorithm'
license='BSD-2-Clause AND GPL-2.0-or-later'
origin=lz4
repo=saphira
url=https://lz4.github.io/lz4/
lz4_sha256=537512904744b35e232912055ccf8ec66d768639ff3abe5788d90d792ec5f48b
depends=""
makedepends="gcc make"
subpackages="$pkgname-dev"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/lz4-1.10.0.tar.gz"
	make -C "$SRC" -j${JOBS:-$(nproc)} PREFIX=/usr BUILD_SHARED=yes CC=gcc
}
recipe_install() {
	make -C "$SRC" install PREFIX=/usr BUILD_SHARED=yes DESTDIR="$PKGDEST" CC=gcc
}
