#!/bin/sh

pkgname=kmod
pkgver=34.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Linux kernel module handling"
license="GPL-2.0-or-later AND LGPL-2.1-or-later"
origin=kmod
repo=main
url=https://git.kernel.org/pub/scm/utils/kernel/kmod/kmod.git
source=https://www.kernel.org/pub/linux/utils/kernel/kmod/kmod-${pkgver}.tar.gz
sha256=d60a79fb12a85feab75674ce5b86b2c8bae1714f775f481eae926bd2657b2ffe

depends="
    zlib
    zstd
"

makedepends="
    binutils
    gcc
    meson
    pkgconf
    zlib-dev
    zstd-dev
"

subpackages="
    $pkgname-dev
"

recipe_build()
{
	meson setup "$BUILDDIR" "$SRC" \
		--prefix=/usr \
		--libdir=/usr/lib \
		-Dxz=disabled \
		-Dopenssl=disabled \
		-Dmanpages=false
	ninja -C "$BUILDDIR"
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C "$BUILDDIR" install
}
