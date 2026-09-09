#!/bin/sh

# I/O top: per-process block I/O accounting (C rewrite, not the old
# Python iotop). Needs a kernel with taskstats; degrades to an
# explicit error where unavailable.

pkgname=iotop
pkgver=1.31
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Per-process I/O monitor (C rewrite)"
license="GPL-2.0-only"
origin=iotop
repo=saphira
url=https://github.com/Tomas-M/iotop
source=https://github.com/Tomas-M/iotop/archive/refs/tags/v1.31.tar.gz
sha256=658a615eb1def9dddcf0c325efebb4f78b101a040fff33ef7afaaa39c2471669

depends="
    ncurses
"

makedepends="
    binutils
    gcc
    make
    ncurses-dev
"

recipe_build()
{
	make -j${JOBS:-$(nproc)} CC=gcc
}

recipe_install()
{
	make DESTDIR="$PKGDEST" PREFIX=/usr install
}
