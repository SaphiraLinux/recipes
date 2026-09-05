#!/bin/sh

pkgname=ifupdown
pkgver=0.12.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="ifupdown-ng: network interface bring-up tools with ifupdown compatibility"
license="BSD-3-Clause"
origin=ifupdown
repo=saphira
url=https://github.com/ifupdown-ng/ifupdown-ng
source=https://github.com/ifupdown-ng/ifupdown-ng/archive/refs/tags/ifupdown-ng-0.12.1.tar.gz
sha256=d42c8c18222efbce0087b92a14ea206de4e865d5c9dde6c0864dcbb2b45f2d85

makedepends="
    binutils
    gcc
    make
"

# Proven v0 build (Makefile flags preserved).
# Stage4 interfaces.example not carried over; no native equivalent in this recipe.
recipe_build()
{
	make -C "$SRC" CFLAGS="${CFLAGS-}" LDFLAGS="${LDFLAGS-}"
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" PREFIX=/usr \
		SYSCONFDIR=/etc install
	rm -rf "$PKGDEST/usr/lib/dinit.d"
}
