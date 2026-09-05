#!/bin/sh

pkgname=libqb
pkgver=2.0.3
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Library providing high performance client server reusable features (glue for resource-agents)'
license='LGPL-2.1-or-later'
origin=libqb
repo=saphira
url=https://github.com/ClusterLabs/libqb
source=https://github.com/ClusterLabs/libqb/releases/download/v${pkgver}/libqb-${pkgver}.tar.xz
sha256=a74582bc886fa625f5238374c7c8ca98672a2519c8196b91276be55886d84e9c

depends=""
makedepends="
	gcc
	glib-dev
	libxml2-dev
	make
	pkgconf
"

subpackages="$pkgname-dev"

recipe_build()
{
	mkdir -p "$BUILDDIR"
	cd "$BUILDDIR"
	../source/configure \
		--prefix=/usr \
		--disable-static
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$BUILDDIR" DESTDIR="$PKGDEST" install
	find "$PKGDEST" -name '*.la' -delete
}
