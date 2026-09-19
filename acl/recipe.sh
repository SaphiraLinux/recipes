#!/bin/sh

pkgname=acl
pkgver=2.4.0
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Access Control List filesystem support"
license="LGPL-2.1-or-later"
origin=acl
repo=main
url=https://savannah.nongnu.org/projects/acl/
source=https://download-mirror.savannah.gnu.org/releases/acl/acl-${pkgver}.tar.xz
sha256=e661131456d2708a01c614a0f400e11d7d1bfaeb6f3e74b75bb980b72f0161a3

depends="
    attr
"

makedepends="
    attr-dev
    gcc
    make
    pkgconf
"

subpackages="
    $pkgname-dev
    $pkgname-doc
"

recipe_build()
{
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	"$SRC/configure" \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--libdir=/usr/lib \
		--disable-static
	make
}

recipe_install()
{
	cd "$BUILDDIR"
	DESTDIR="$PKGDEST" make install
	mkdir -p "$PKGDEST/lib"
}
