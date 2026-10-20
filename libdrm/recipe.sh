#!/bin/sh
pkgname=libdrm
pkgver=2.4.134
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Direct Rendering Manager user-space library (KMS API for Intel/AMD/NVIDIA/ARM GPUs)'
license='MIT'
origin=libdrm
repo=saphira
url=https://dri.freedesktop.org/
source=https://dri.freedesktop.org/libdrm/libdrm-2.4.134.tar.xz
sha256=ac5e74d157830eb8bee44c6a6bf3ad49774ef0dd2a72bdad74a8f20308b52a95

# libpciaccess carries the Intel KMS backend (proven same-edge as
# libvirt, which runtime-depends on it for nodedev). Man pages are
# built from the shipped .rst sources via rst2man (in-tree
# python-docutils) and ship in the -doc split - no doc generator is
# missing, so nothing is disabled.
depends="libpciaccess"
makedepends="
	binutils
	gcc
	meson
	ninja
	pkgconf
	libpciaccess
	python-docutils
	saphira-linux-uapi-headers
"

subpackages="$pkgname-dev $pkgname-doc"

recipe_build()
{
	meson setup build "$SRC" \
		--prefix=/usr \
		-Dlibdir=lib \
		-Dintel=enabled -Dradeon=enabled -Damdgpu=enabled \
		-Dnouveau=enabled -Dvmwgfx=enabled \
		-Domap=enabled -Dexynos=enabled -Dfreedreno=enabled \
		-Dtegra=enabled -Dvc4=enabled -Detnaviv=enabled \
		-Dcairo-tests=disabled -Dman-pages=enabled \
		-Dvalgrind=disabled \
		-Dudev=true -Dtests=false
	meson compile -C build
}

recipe_install()
{
	DESTDIR="$PKGDEST" meson install -C build
}
