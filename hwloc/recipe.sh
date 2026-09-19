#!/bin/sh

# Hardware topology library and tools (lstopo). Cairo/libxml2 output
# formats stay off: no graphics or XML stack on servers, textual and
# programmatic topology is the deliverable.

pkgname=hwloc
pkgver=2.14.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Hardware topology library and lstopo"
license="BSD-3-Clause"
origin=hwloc
repo=saphira
url=https://www.open-mpi.org/projects/hwloc/
source=https://download.open-mpi.org/release/hwloc/v2.14/hwloc-2.14.0.tar.bz2
sha256=966b9bb3e9f29f8d65ce8d106779e457f40e246a645e584b100772a42f9ae94b

depends=""

makedepends="
    binutils
    gcc
    make
    pkgconf
"

recipe_build()
{
	./configure --prefix=/usr --sysconfdir=/etc \
		--localstatedir=/var \
		--disable-cairo --disable-libxml2
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
}
