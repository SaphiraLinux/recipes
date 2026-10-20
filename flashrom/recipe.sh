#!/bin/sh
pkgname=flashrom
pkgver=1.8.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='SPI flash programmer (internal, Linux SPI, USB, FTDI, J-Link, GPIO)'
license='GPL-2.0-only'
origin=flashrom
repo=saphira
url=https://www.flashrom.org/
# Current stable at packaging time; upstream-published sha256 matches.
source=https://download.flashrom.org/releases/flashrom-v1.8.0.tar.xz
sha256=654c9c61745c250cd3b5ccd0e56fc43ee76980f92a5e078420420639d66975a2

# Runtime closure mirrors the enabled programmer backends below.
depends="libftdi1 libjaylink libusb pciutils"
# Programmer matrix (meson -Dprogrammer=, all soft-selected so a missing
# dep skips with a message instead of failing; the verified matrix is in
# the commit message):
#  group_internal (internal incl. chipset/SPI on x86_64, linux_mtd,
#    PCI NIC/SATA programmers) via libpci (pciutils-dev);
#  group_external + group_serial (serprog, buspirate, pony, spidriver);
#  group_ftdi (ft2232_spi, usbblaster_spi) via libftdi1-dev;
#  group_jlink (jlink_spi) via libjaylink-dev;
#  group_usb (ch341a/ch347, dediprog, digilent, dirtyjtag, pickit2,
#    raiden, stlinkv3, ...) via libusb-dev;
#  group_i2c (mediatek/mstarddc/realtek LSPCon; Linux-only helpers);
#  linux_spi + dummy named explicitly (they belong to no group; dummy
#    exists so safe read-only/probe tests never touch real flash).
# Deliberately excluded, not silent: ni845x_spi (Windows-only, x86
#  32-bit, proprietary NI library); man-pages/documentation (need
#  sphinx-build, not in tree — full --help ships in the binary);
#  unit tests (need cmocka; bundled 1.1.8 fails under gcc 16 -Werror,
#  and no system cmocka is packaged — safe dummy-programmer tests run
#  separately against the installed binary).
makedepends="binutils gcc libftdi1-dev libjaylink-dev libusb-dev make meson ninja pciutils-dev pkgconf saphira-linux-uapi-headers"

recipe_build() {
	FLASH_BALL="$RECIPE_DIR/files/flashrom-v${pkgver}.tar.xz"
	echo "$sha256  $FLASH_BALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$FLASH_BALL"
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	meson setup "$SRC" \
		--prefix=/usr \
		--libdir=lib \
		--buildtype=release \
		-Dprogrammer=group_internal,group_external,group_ftdi,group_jlink,group_pci,group_serial,group_usb,group_i2c,linux_spi,dummy \
		-Dtests=disabled \
		-Dman-pages=disabled \
		-Ddocumentation=disabled
	meson compile
}

recipe_install() {
	DESTDIR="$PKGDEST" meson install -C "$BUILDDIR"
	# Upstream default_library=both is required for classic_cli; drop
	# the static archive per Saphira shared-only policy.
	find "$PKGDEST" -name '*.a' -delete
}
