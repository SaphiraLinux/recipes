#!/bin/sh
pkgname=libepoxy
pkgver=1.5.10
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='OpenGL function pointer management (EGL dispatch for headless rendering, no X11)'
license='MIT'
origin=libepoxy
repo=saphira
url=https://github.com/anholt/libepoxy
source=https://github.com/anholt/libepoxy/archive/refs/tags/1.5.10.tar.gz
sha256=a7ced37f4102b745ac86d6a70a9da399cc139ff168ba6b8002b4d8d43c900c15

# EGL-only dispatch: glx=no, x11=false (headless policy - no X stack).
# EGL headers and libEGL come from the in-tree mesa (surfaceless+GBM).
# API docs built with the packaged doxygen (dot graphs degrade
# gracefully when graphviz is absent) and ship in the -doc split.
depends="mesa"
makedepends="
	binutils
	gcc
	meson
	ninja
	pkgconf
	python3
	mesa
	mesa-dev
	doxygen
"

subpackages="$pkgname-dev $pkgname-doc"

recipe_build()
{
	meson setup build "$SRC" \
		--prefix=/usr \
		-Dlibdir=lib \
		-Dglx=no -Degl=yes -Dx11=false -Dtests=false -Ddocs=true
	meson compile -C build
}

recipe_install()
{
	DESTDIR="$PKGDEST" meson install -C build
}
