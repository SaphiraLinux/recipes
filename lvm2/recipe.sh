#!/bin/sh

# LVM2 logical volume management. udev integration is off: no udev
# headers exist in the tree, and storage tooling must not depend on
# the device manager being present at build time. If udev lands
# later, drop --disable-udev_sync deliberately (an unknown spelling
# would only warn under autoconf, so a wrong flag here fails safe
# and loud at configure time, not silently).

pkgname=lvm2
pkgver=2.03.39
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Logical volume management"
license="GPL-2.0-or-later LGPL-2.1-or-later"
origin=lvm2
repo=saphira
url=https://sourceware.org/lvm2/
source=https://github.com/lvmteam/lvm2/archive/refs/tags/v2_03_39.tar.gz
sha256=af2969dd2dff34663bb6f5777b8636f17956e5403c8d809231009fdea9dc46d8

# device/bcache.c includes <libaio.h> unconditionally (proven by the
# 2026-10-17 grub-2.14 dependency build: lvm2 failed with
# "fatal error: libaio.h: No such file or directory"). libaio-dev
# supplies the headers at build time, libaio the runtime library.
depends="
    readline
    libaio
"

makedepends="
    binutils
    gcc
    make
    pkgconf
    readline-dev
    libaio-dev
"

recipe_build()
{
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/v2_03_39.tar.gz"
	echo "$sha256  $RECIPE_DIR/files/v2_03_39.tar.gz" | sha256sum -c -
	# musl: stdin/stdout/stderr are not assignable lvalues (glibc-ism
	# in _check_standard_fds: "assignment of read-only variable").
	# freopen() reopens the stream in place and is portable to glibc.
	patch -p1 -d "$SRC" < "$RECIPE_DIR/files/musl-stdio-assign.patch"
	cd "$SRC"
	./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
		--disable-udev_sync
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
}
