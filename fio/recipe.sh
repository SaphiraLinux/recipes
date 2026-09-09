#!/bin/sh

# Flexible I/O tester for storage validation. libaio engine enabled
# (libaio is published); remaining engines degrade gracefully at
# configure time if their headers are absent.

pkgname=fio
pkgver=3.42
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Flexible I/O tester"
license="GPL-2.0-only"
origin=fio
repo=saphira
url=https://github.com/axboe/fio
source=https://github.com/axboe/fio/archive/refs/tags/fio-3.42.tar.gz
sha256=56b03497a918d07692257890fd759bf73168ad79df5be78a2bcbbdc8ce67895b

depends="
    libaio
"

makedepends="
    binutils
    gcc
    libaio-dev
    make
"

recipe_build()
{
	./configure --prefix=/usr
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
}
