#!/bin/sh

# LVM2 logical volume management. udev integration is off: no udev
# headers exist in the tree, and storage tooling must not depend on
# the device manager being present at build time. If udev lands
# later, drop --disable-udev_sync deliberately (an unknown spelling
# would only warn under autoconf, so a wrong flag here fails safe
# and loud at configure time, not silently).
#
# musl stdio: stdin/stdout/stderr are not assignable lvalues
# (glibc-ism), and glibc-specific setlinebuf/linebuffer juggling in
# toolcontext.c corrupts musl stdio (every tool segfaulted right
# after fd setup; strace-proven). The musl-stdio-assign.patch covers
# both (freopen + #ifdef __GLIBC__ guards, same approach as Alpine's
# fix-stdio-usage.patch).

pkgname=lvm2
pkgver=2.03.39
pkgrel=4
# r4: three-way split (main tools, lvm2-libs runtime, lvm2-dev headers);
# headers no longer force tool installs, main takes lvm2-libs for its
# linked binaries. Payload change.
# r3: initramfs LVM-root hook (files/20-lvm-activate ->
# /lib/saphira/initramfs/root.d/, suite-proven): vgchange -ay plus
# mounting root=/dev/mapper/... at /newroot, else activation only so
# /init mounts plain roots itself. Inert until a media builder names
# it in an initramfs.conf with `bin vgchange`; the default base
# initramfs is untouched.
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
#
# Three-way split (headers must never force tool installs): lvm2-dev
# carries usr/include plus the link-time names, lvm2-libs the SONAME
# runtime (standalone, no parent pin), and main keeps the tools, udev
# state, config and the initramfs hook. Consumers take -dev to build
# and -libs to run; nothing takes main for headers.
subpackages="lvm2-dev lvm2-libs"
depends="
    readline
    libaio
    lvm2-libs
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
	sh "$RECIPE_DIR/tests/lvm-activate-hook.sh" ||
		{ echo "ERROR: lvm-activate-hook suite failed" >&2; return 1; }
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/v2_03_39.tar.gz"
	echo "$sha256  $RECIPE_DIR/files/v2_03_39.tar.gz" | sha256sum -c -
	# musl stdio patch (freopen + __GLIBC__ guards, see header).
	patch -p1 -d "$SRC" < "$RECIPE_DIR/files/musl-stdio-assign.patch"
	cd "$SRC"
	./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
		--disable-udev_sync
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
	# LVM-root initramfs hook (inert file until composed into an
	# initramfs.conf; see its header for the composition contract).
	install -D -m 0755 "$RECIPE_DIR/files/20-lvm-activate" \
		"$PKGDEST/lib/saphira/initramfs/root.d/20-lvm-activate"
}
