#!/bin/sh

pkgname=libdaemon
pkgver=0.14
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Lightweight C library that eases the writing of UNIX daemons"
license="LGPL-2.1-or-later"
origin=libdaemon
repo=main
url=http://0pointer.de/lennart/projects/libdaemon
source=http://0pointer.de/lennart/projects/libdaemon/libdaemon-${pkgver}.tar.gz
sha256=fd23eb5f6f986dcc7e708307355ba3289abe03cc381fc47a80bca4a50aa6b834

depends=""

makedepends="
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
	cd "$SRC"
	# musl: <sys/unistd.h> does not exist; the C POSIX library
	# recommends <unistd.h> (carried as a vendored patch from the
	# cports guidance tree, attributable to Jorg Krause).
	patch -p1 < "$RECIPE_DIR/files/libdaemon-musl-unistd.patch"
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	"$SRC/configure" \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--libdir=/usr/lib \
		--disable-static \
		--disable-lynx
	make
}

recipe_install()
{
	cd "$BUILDDIR"
	DESTDIR="$PKGDEST" make install
}
