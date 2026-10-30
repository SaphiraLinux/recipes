#!/bin/sh

pkgname=libglvnd
pkgver=1.7.0
pkgrel=1
# r1: vendor-neutral GL dispatch (2026-10-23). Saphira's virgl/GL stack
# could never render: vrend issues desktop-GL calls through epoxy,
# which resolves them ONLY via libOpenGL.so.0/libGL.so.1, and mesa
# builds glx+glvnd disabled so NEITHER existed (proven on published
# qemu r8 + mesa r3: 'Couldn't open libGL.so.1 or libOpenGL.so.0').
# This package supplies the missing libOpenGL dispatch (+ libEGL/
# libGLES dispatch) with NO X stack: x11/glx/hgl off, egl/gles/opengl
# on. Upstream sets EGL_NO_X11 unconditionally - EGL dispatch makes
# no assumption about native displays. mesa flips to -Dglvnd=enabled
# alongside (its libs become libEGL_mesa-style vendors, no SONAME
# collision with the dispatch libs here). Single package, no per-lib
# splits: upstream requires split libglvnd libraries to carry matched
# inter-dependencies, which a single package satisfies trivially.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Vendor-neutral OpenGL dispatch (X-free: EGL/GLES/OpenGL dispatch, no GLX)"
license="MIT"
origin=libglvnd
repo=saphira
url=https://gitlab.freedesktop.org/glvnd/libglvnd
source=https://gitlab.freedesktop.org/glvnd/libglvnd/-/archive/v1.7.0/libglvnd-v1.7.0.tar.gz
sha256=2b6e15b06aafb4c0b6e2348124808cbd9b291c647299eaaba2e3202f51ff2f3d

depends=""

makedepends="
	binutils
	gcc
	meson
	ninja
	pkgconf
	python3
"

subpackages="$pkgname-dev $pkgname-doc"

recipe_build()
{
	tar --no-same-owner -C "$SRC" --strip-components=1 \
		-xf "$RECIPE_DIR/files/libglvnd-v1.7.0.tar.gz"
	# NOTE: no comment lines inside the \-continued command below.
	meson setup "$BUILDDIR" "$SRC" \
		--prefix=/usr \
		-Dlibdir=lib \
		--buildtype=release \
		-Dx11=disabled \
		-Dglx=disabled \
		-Dhgl=false \
		-Degl=true \
		-Dgles1=true \
		-Dgles2=true \
		-Dheaders=true
	ninja -C "$BUILDDIR"
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C "$BUILDDIR" install
}
