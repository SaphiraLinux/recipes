#!/bin/sh

pkgname=traceroute
pkgver=2.1.6
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Traces the route taken by packets across an IP network (IPv4 and IPv6)'
license='GPL-2.0-or-later LGPL-2.1-or-later'
origin=traceroute
repo=saphira
url=http://traceroute.sourceforge.net/
source=https://sourceforge.net/projects/traceroute/files/traceroute/traceroute-${pkgver}/traceroute-${pkgver}.tar.gz
sha256=9ccef9cdb9d7a98ff7fbf93f79ebd0e48881664b525c4b232a0fcec7dcb9db5e

depends=""
makedepends="gcc make"

recipe_build()
{
	make -C "$SRC" -j${JOBS:-$(nproc)} prefix=/usr \
		CC=gcc CFLAGS="-O2 -D_GNU_SOURCE" LDFLAGS=""
	"$SRC"/traceroute/traceroute --version 2>&1 | grep -qi traceroute
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" prefix=/usr install
	install -d "$PKGDEST/usr/bin"
	ln -s traceroute "$PKGDEST/usr/bin/traceroute6"
	test -x "$PKGDEST/usr/bin/traceroute"
}
