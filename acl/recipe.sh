#!/bin/sh

pkgname=acl
pkgver=2.3.2
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Access Control List filesystem support"
license="LGPL-2.1-or-later"
origin=acl
repo=main
url=https://savannah.nongnu.org/projects/acl/
source=https://download-mirror.savannah.gnu.org/releases/acl/acl-${pkgver}.tar.xz
sha256=97203a72cae99ab89a067fe2210c1cbf052bc492b479eca7d226d9830883b0bd

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
		--libdir=/usr/lib \
		--disable-static
	make
}

recipe_install()
{
	cd "$BUILDDIR"
	DESTDIR="$PKGDEST" make install
	mkdir -p "$PKGDEST/lib"
	for library in "$PKGDEST/usr/lib/libacl.so.1" \
		"$PKGDEST/usr/lib/libacl.so.1."*; do
		[ -e "$library" ] || [ -L "$library" ] || continue
		mv "$library" "$PKGDEST/lib/"
	done
	rm -f "$PKGDEST/usr/lib/libacl.so"
	ln -s "../../lib/libacl.so.1."* "$PKGDEST/usr/lib/libacl.so"
}
