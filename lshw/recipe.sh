#!/bin/sh

# Hardware lister. Reads pci.ids/hwdata at runtime (present on targets
# via hwdata); numeric IDs still work without it.

pkgname=lshw
pkgver=02.20
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Hardware lister"
license="GPL-2.0-only"
origin=lshw
repo=saphira
url=https://ezix.org/project/lshw.html
source=https://github.com/lyonel/lshw/archive/refs/tags/B.02.20.tar.gz
sha256=6b8346a89fb0f0f1798e66f6a707a881d38b9b3a67256b30fc4628dac09f291a

depends="
    hwdata
"

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
	make DESTDIR="$PKGDEST" PREFIX=/usr install
}
