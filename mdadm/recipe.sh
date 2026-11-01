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

depends="udev"

makedepends="
    binutils
    gcc
    make
    udev-dev
"
# udev: monitor mode links libudev (udev.h + -ludev).

recipe_build()
{
	# files/ patch: Makefile assigns CFLAGS unconditionally, so env
	# flags never reach the compiler; the -Werror carve-out ships
	# as a patch instead (see PATCHES.md).
	patch -d "$SRC" -Np1 \
		-i "$RECIPE_DIR/files/0001-gcc16-unused-but-set-variable.patch"
	make -j${JOBS:-$(nproc)} CC=gcc
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
}
