#!/bin/sh

# Software RAID management tooling.

pkgname=mdadm
pkgver=4.4
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Software RAID management"
license="GPL-2.0-or-later"
origin=mdadm
repo=saphira
url=https://raid.wiki.kernel.org/
source=https://kernel.org/pub/linux/utils/raid/mdadm/mdadm-4.4.tar.xz
sha256=9b488f35ed153df99924b5fe41eed380e8512de8f18a118628cacdd681b1d573

depends=""

makedepends="
    binutils
    gcc
    make
"

recipe_build()
{
	make -j${JOBS:-$(nproc)} CC=gcc
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
}
