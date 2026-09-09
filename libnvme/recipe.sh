#!/bin/sh

# NVMe utility library (nvme-cli backend). Headers split to -dev;
# consumers (nvme-cli) take libnvme-dev.

pkgname=libnvme
pkgver=1.16.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="NVMe utility library"
license="LGPL-2.1-or-later"
origin=libnvme
repo=saphira
url=https://github.com/linux-nvme/libnvme
source=https://github.com/linux-nvme/libnvme/archive/refs/tags/v1.16.2.tar.gz
sha256=1d850d5a871559abf641d6e6b63bb86047e4cb26f3ad144597c2c64b3cff7231

depends="
    json-c
"

makedepends="
    binutils
    gcc
    json-c-dev
    meson
    ninja
    pkgconf
"

subpackages="libnvme-dev"

recipe_build()
{
	meson setup --prefix=/usr --buildtype=release "$BUILDDIR" "$SRC"
	ninja -C "$BUILDDIR" -j${JOBS:-$(nproc)}
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C "$BUILDDIR" install
}
