#!/bin/sh

# Software RAID management tooling.

pkgname=mdadm
pkgver=4.6
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Software RAID management"
license="GPL-2.0-or-later"
origin=mdadm
repo=saphira
url=https://raid.wiki.kernel.org/
source=https://github.com/md-raid-utilities/mdadm/archive/refs/tags/mdadm-4.6.tar.gz
sha256=202a7525e6f2b44395a9ef2c561082c7d6d8204e9addfe3f6268bfb141efc093

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
	# files/ patches: Makefile assigns CFLAGS unconditionally, so env
	# flags never reach the compiler; the -Werror carve-out ships
	# as a patch instead, plus gcc15+ -Werror source fixes
	# (see PATCHES.md). 0002 is kept for the 4.4 record but not
	# applied: upstream 4.6 carries the nonstring attribute itself.
	patch -d "$SRC" -Np1 \
		-i "$RECIPE_DIR/files/0001-gcc16-unused-but-set-variable.patch"
	patch -d "$SRC" -Np1 \
		-i "$RECIPE_DIR/files/0003-missing-disk-index-clamp.patch"
	patch -d "$SRC" -Np1 \
		-i "$RECIPE_DIR/files/0004-install-via-path.patch"
	make -j${JOBS:-$(nproc)} CC=gcc
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
}
