#!/bin/sh

pkgname=usbutils
pkgver=019
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='USB utilities (lsusb) - device names and vid:pid via usb.ids/hwdb'
license='GPL-2.0-or-later'
origin=usbutils
repo=saphira
url=https://www.kernel.org/pub/linux/utils/usb/usbutils/
# Vendored: https://www.kernel.org/pub/linux/utils/usb/usbutils/usbutils-019.tar.xz
usbutils_sha256=659f40c440e31ba865c52c818a33d3ba6a97349e3353f8b1985179cb2aa71ec5

depends="libusb udev hwdata"
makedepends="
	binutils
	gcc
	libusb-dev
	saphira-kernel-headers=7.1.5
	meson
	ninja
	pkgconf
	udev-dev
"

recipe_build()
{
	UBALL="$RECIPE_DIR/files/usbutils-019.tar.xz"
	echo "$usbutils_sha256  $UBALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$UBALL"
	meson setup build "$SRC" \
		--prefix=/usr \
		-Dlibdir=lib
	meson compile -C build
}

recipe_install()
{
	DESTDIR="$PKGDEST" meson install -C build
}
