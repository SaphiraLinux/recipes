#!/bin/sh
pkgname=virglrenderer
pkgver=1.3.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='VirGL virtual GPU renderer (accelerated virtio-gpu for QEMU guests)'
license='MIT'
origin=virglrenderer
repo=saphira
url=https://virgil3d.github.io/
source=https://gitlab.freedesktop.org/virgl/virglrenderer/-/archive/1.3.0/virglrenderer-1.3.0.tar.gz
sha256=065bc56e89e6f631f96101cd62eba0748e48eb888b434edc86e89d05395e76f3

# Classic VirGL path (host GL via EGL/GBM): platforms=egl only (no glx
# without X11). Venus (Vulkan) stays off - it belongs to the rutabaga/
# gfxstream follow-up with its Vulkan and Rust closure. drm native
# renderers stay at upstream default (experimental). video stays off
# (needs libva, not packaged - filed as follow-up, not silently cut:
# the default is off upstream too).
depends="libdrm libepoxy mesa"
# Build-time python3-yaml is required, not optional:
# src/gallium/meson.build fails closed ("python3 is missing modules:
# yaml") without it. Proven by retained-workspace build failure, not
# assumed (pyyaml is what mesa already uses for the same probe).
makedepends="
	binutils
	gcc
	meson
	ninja
	pkgconf
	python3
	pyyaml
	libdrm
	libdrm-dev
	libepoxy
	libepoxy-dev
	mesa
	mesa-dev
"

subpackages="$pkgname-dev"

recipe_build()
{
	meson setup build "$SRC" \
		--prefix=/usr \
		-Dlibdir=lib \
		-Dplatforms=egl \
		-Dvenus=false -Dvideo=false -Dtests=false
	meson compile -C build
}

recipe_install()
{
	DESTDIR="$PKGDEST" meson install -C build
}
