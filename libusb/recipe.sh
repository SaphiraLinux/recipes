#!/bin/sh

pkgname=libusb
pkgver=1.0.30
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Library for USB device access from userspace'
license='LGPL-2.1-or-later'
origin=libusb
repo=saphira
url=https://libusb.info/
# Vendored: https://github.com/libusb/libusb/releases/download/v1.0.30/libusb-1.0.30.tar.bz2
libusb_sha256=fea36f34f9156400209595e300840767ab1a385ede1dc7ee893015aea9c6dbaf

depends="udev"
makedepends="
	binutils
	bzip2
	gawk
	gcc
	make
	udev-dev
"

subpackages="$pkgname-dev"

recipe_build()
{
	LUBALL="$RECIPE_DIR/files/libusb-1.0.30.tar.bz2"
	echo "$libusb_sha256  $LUBALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$LUBALL"
	cd "$SRC"
	./configure --prefix=/usr --disable-static --enable-shared \
		--disable-udev-systemd-timer
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
