#!/bin/sh
pkgname=i2c-tools
pkgver=4.4
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='I2C/SMBus inspection tools plus libi2c (i2cdetect/i2cget/i2cset/i2cdump)'
license='GPL-2.0-or-later LGPL-2.1-or-later'
origin=i2c-tools
repo=saphira
url=https://git.kernel.org/pub/scm/utils/i2c-tools/i2c-tools.git/
source=https://git.kernel.org/pub/scm/utils/i2c-tools/i2c-tools.git/snapshot/i2c-tools-4.4.tar.gz
sha256=af01d0fbe78e109a2db7137c7e9bfda3f3fb236c3177744c0f2695d1056cde71

# eeprom/ decode scripts are perl; they install to bindir by default.
depends="perl"
# EXTRA=eeprog builds upstream's 24Cxx EEPROM tool alongside the probing
# family (fits the firmware toolkit; py-smbus stays out of scope).
# BUILD_STATIC_LIB=0: shared libi2c only, per Saphira policy.
makedepends="binutils gcc make saphira-linux-uapi-headers"
subpackages="$pkgname-dev"

recipe_build() {
	I2C_BALL="$RECIPE_DIR/files/i2c-tools-${pkgver}.tar.gz"
	echo "$sha256  $I2C_BALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$I2C_BALL"
	make -C "$SRC" -j${JOBS:-$(nproc)} \
		PREFIX=/usr libdir=/usr/lib \
		BUILD_STATIC_LIB=0 EXTRA=eeprog
}

recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" \
		PREFIX=/usr libdir=/usr/lib \
		BUILD_STATIC_LIB=0 EXTRA=eeprog install
}
