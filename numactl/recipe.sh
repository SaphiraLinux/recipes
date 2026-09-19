#!/bin/sh

# NUMA policy library and tools. libnuma headers ship in the main
# package (libpng precedent: no -dev split for this small library),
# so consumers depend on numactl directly.

pkgname=numactl
pkgver=2.0.19
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="NUMA policy library and tools"
license="GPL-2.0-or-later LGPL-2.1-or-later"
origin=numactl
repo=saphira
url=https://github.com/numactl/numactl
source=https://github.com/numactl/numactl/releases/download/v2.0.19/numactl-2.0.19.tar.gz
sha256=f2672a0381cb59196e9c246bf8bcc43d5568bc457700a697f1a1df762b9af884

depends=""

makedepends="
    binutils
    gcc
    make
"

recipe_build()
{
	./configure --prefix=/usr --sysconfdir=/etc --disable-static --localstatedir=/var
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
	# move_pages.2 is canonical man-pages collection content, already
	# owned there: drop our duplicate so the gate stays single-owner.
	rm -f "$PKGDEST/usr/share/man/man2/move_pages.2"
}
