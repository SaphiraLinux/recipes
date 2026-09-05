#!/bin/sh
pkgname=util-linux
pkgver=2.41.1
pkgrel=7
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Miscellaneous Linux utilities (mount, lsblk, blkid, fdisk, dmesg)'
license='GPL-2.0-or-later LGPL-2.1-or-later BSD-3-Clause'
origin=util-linux
repo=saphira
url=https://github.com/util-linux/util-linux
util_linux_sha256=be9ad9a276f4305ab7dd2f5225c8be1ff54352f565ff4dede9628c1aaa7dec57
depends="zlib ncurses"
makedepends="bison flex gcc gettext libxcrypt-dev saphira-kernel-headers=7.1.5 meson ninja pkgconf zlib-dev ncurses-dev"
subpackages="$pkgname-dev $pkgname-doc"
recipe_build()
{
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/util-linux-2.41.1.tar.xz"
	cd "$SRC"
	echo "$util_linux_sha256  $RECIPE_DIR/files/util-linux-2.41.1.tar.xz" | sha256sum -c -
	meson setup _build --prefix=/usr \
		--libdir=/usr/lib \
		-Dsystemd=disabled \
		-Dsysvinit=disabled \
		-Dtinfo=disabled \
		-Deconf=disabled \
		-Dselinux=disabled \
		-Dslang=disabled \
		-Dlibutil=disabled \
		-Dlibuser=disabled \
		-Dlibutempter=disabled \
		-Dreadline=disabled \
		-Dbuild-python=disabled \
	-Dbuild-plymouth-support=disabled \
	-Dbuild-python=disabled \
	-Dbuild-agetty=enabled \
	-Dbuild-chfn-chsh=disabled \
	-Dbuild-newgrp=disabled \
	-Dbuild-login=disabled \
	-Dbuild-nologin=disabled \
	-Dbuild-su=disabled \
	-Dbuild-sulogin=enabled \
	-Dbuild-wall=enabled \
	-Dbuild-write=disabled \
	-Dbuild-cal=enabled \
	-Dbuild-kill=enabled \
	-Dbuild-mesg=enabled \
	-Dbuild-more=enabled \
	-Dbuild-setarch=enabled \
	-Dbuild-switch_root=enabled \
	-Dbuild-vipw=disabled \
		-Dbuild-pam-lastlog2=disabled \
		-Dbuild-liblastlog2=disabled
	meson compile -C _build
}
recipe_install()
{
	DESTDIR="$PKGDEST" meson install -C "$SRC/_build"
	rm -f "$PKGDEST/sbin/nologin"
	# Saphira is deliberately NOT usrmerged: system binaries live in /bin
	# and /sbin, where systemd units and OpenRC init scripts expect them
	# (r2 shipped them under /usr and broke both inits - see the r0/r2/r3
	# boot matrix). Restore the proven r0 layout.
	bin_tools="dmesg findmnt lsblk lsfd more mount mountpoint pipesz umount wdctl"
	sbin_tools="agetty blkdiscard blkid blkpr blkzone blockdev cfdisk chcpu ctrlaltdel fdisk findfs fsck fsck.cramfs fsck.minix fsfreeze fstrim hwclock losetup mkfs mkfs.bfs mkfs.cramfs mkfs.minix mkswap pivot_root sfdisk sulogin swaplabel swapoff swapon switch_root wipefs zramctl"
	install -d "$PKGDEST/bin" "$PKGDEST/sbin"
	for tool in $bin_tools; do
		[ -e "$PKGDEST/usr/bin/$tool" ] && mv "$PKGDEST/usr/bin/$tool" "$PKGDEST/bin/$tool"
	done
	for tool in $sbin_tools; do
		[ -e "$PKGDEST/usr/sbin/$tool" ] && mv "$PKGDEST/usr/sbin/$tool" "$PKGDEST/sbin/$tool"
	done
	# Match the proven r0 modes: upstream meson ships mount/umount
	# setuid 4755 and wall setgid-tty 2755; Saphira's r0 shipped plain
	# 0755 and boots without the special bits.
	chmod 0755 "$PKGDEST/bin/mount" "$PKGDEST/bin/umount" "$PKGDEST/usr/bin/wall"
	# FHS non-usrmerged: /bin|/sbin consumers (mount, fsck, blkid,
	# fdisk family) need the runtime SONAME chain in /lib; dev
	# linker names stay in /usr/lib pointing back (acl precedent).
	mkdir -p "$PKGDEST/lib"
	for lib in "$PKGDEST/usr/lib/libblkid.so.1"* "$PKGDEST/usr/lib/libmount.so.1"* \
		"$PKGDEST/usr/lib/libsmartcols.so.1"* "$PKGDEST/usr/lib/libfdisk.so.1"* \
		"$PKGDEST/usr/lib/libuuid.so.1"*; do
		[ -e "$lib" ] && mv "$lib" "$PKGDEST/lib/"
	done
	for dev in libblkid.so libmount.so libsmartcols.so libfdisk.so libuuid.so; do
		link="$PKGDEST/usr/lib/$dev"
		[ -L "$link" ] || continue
		target=$(readlink "$link")
		case $target in */*) continue;; esac
		[ -e "$PKGDEST/lib/$target" ] && ln -sf "../../lib/$target" "$link"
	done
}
