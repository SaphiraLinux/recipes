#!/bin/sh

# NVMe command-line management. Optional auto-detected integrations
# (udev/systemd) link only what the build root provides; verify with
# `ldd /usr/sbin/nvme | grep 'not found'` on the target after install.

pkgname=nvme-cli
pkgver=3.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="NVMe command-line management tool"
license="GPL-2.0-only"
origin=nvme-cli
repo=saphira
url=https://github.com/linux-nvme/nvme-cli
source=https://github.com/linux-nvme/nvme-cli/archive/refs/tags/v3.0.tar.gz
sha256=37db80e4303403434f169265be4c0f28fedbc37862a54ad49c7cb289f677c6fe

depends="
    libnvme
"

makedepends="
    binutils
    gcc
    libnvme-dev
    meson
    ninja
    pkgconf
"

recipe_build()
{
	meson setup --prefix=/usr --sysconfdir=/etc --buildtype=release "$BUILDDIR" "$SRC"
	ninja -C "$BUILDDIR" -j${JOBS:-$(nproc)}
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C "$BUILDDIR" install
}
