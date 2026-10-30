#!/bin/sh

pkgname=linux-firmware-full
pkgver=20260910
pkgrel=1
# r1: full-set meta (2026-10-23). The seven linux-firmware family
# splits auto-pin their base release, so the meta cannot live inside
# the linux-firmware recipe itself (INSTALL-gate version conflict,
# proven on r3): it lives here, outside the pinned family, depending
# on the published splits. Bare `apk add linux-firmware` is licence
# evidence only; THIS is the install-everything package (usb-installer
# profile, unknown target hardware).
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="All linux-firmware families (meta: intel/i915/amd/nvidia/qcom/network/misc)"
license="linux-firmware licence"
origin=linux-firmware-full
repo=saphira
url=https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git

depends="linux-firmware-intel linux-firmware-i915 linux-firmware-amd linux-firmware-nvidia linux-firmware-qcom linux-firmware-network linux-firmware-misc"

recipe_build()
{
	:
}

recipe_install()
{
	install -D -m 0644 "$RECIPE_DIR/files/README" \
		"$PKGDEST/usr/share/doc/linux-firmware-full/README"
}
