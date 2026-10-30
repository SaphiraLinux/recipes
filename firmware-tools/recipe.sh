#!/bin/sh
pkgname=firmware-tools
pkgver=0.1
pkgrel=2
# r2: LICENSE gains an explicit scope section (2026-10-23): BUSL-1.1
# covers ONLY the Saphira-authored grouping/notice, never the GPL/MIT
# member software (each keeps its upstream licence, listed in the
# scope table). The license= field stays BUSL-1.1 for the wrapper per
# Saphira-owned-software policy (saphira-base metapackage precedent);
# changing it would need an explicit policy decision, not a silent
# relicense of Saphira's own compilation copyright.
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
