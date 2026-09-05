#!/bin/sh

pkgname=libucontext
pkgver=1.5.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="ucontext implementation featuring glibc-compatible ABI"
license="ISC"
origin=libucontext
repo=main
url=https://github.com/kaniini/libucontext
source=https://github.com/kaniini/libucontext/archive/refs/tags/libucontext-${pkgver}.tar.gz
sha256=9230397327bbf580e04c9456d1509e9af19599c7f6deca7f75969ece6e9d598e

depends=""

makedepends="
    binutils
    gcc
    meson
    pkgconf
"

subpackages="
    $pkgname-dev
"

recipe_build()
{
	meson setup "$BUILDDIR" "$SRC" \
		--prefix=/usr \
		--libdir=/usr/lib \
		-Ddocs=false
	ninja -C "$BUILDDIR"
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C "$BUILDDIR" install
}
