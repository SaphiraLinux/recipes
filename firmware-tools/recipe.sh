#!/bin/sh
pkgname=firmware-tools
pkgver=0.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Saphira firmware toolkit group (safe inspection/programming tools)'
license='BUSL-1.1'
origin=firmware-tools
repo=saphira
url=https://saphira.vm2.uk/

# Metapackage: carries no payload of its own (saphira-base precedent).
# Safe inspection/programming members only. chipsec stays out by
# policy; intel-lms and fwupd are blocked (see project record);
# proprietary Intel tools are never redistributed.
depends="
	dmidecode
	efibootmgr
	efivar
	flashrom
	coreboot-tools
	i2c-tools
	libconfuse
	libftdi1
	libgpiod
	libjaylink
	me-analyzer
	me-cleaner
	mei-amt-check
	metee
	msr-tools
	pciutils
	uefi-tools
	usbutils
"
makedepends=""

recipe_build()
{
	:
}

recipe_install()
{
	install -D -m 0644 "$RECIPE_DIR/files/README.group" \
		"$PKGDEST/usr/share/doc/firmware-tools/README.group"
	install -D -m 0644 "$RECIPE_DIR/files/LICENSE" \
		"$PKGDEST/usr/share/licenses/firmware-tools/LICENSE"
}
