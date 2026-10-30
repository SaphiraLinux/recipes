#!/bin/sh

pkgname=mesa-demos
pkgver=9.0.0
pkgrel=1
# r1: EGL/GLES validation tools (2026-10-23). Headless subset only:
# eglinfo (+ es2gears and the EGL gears) with x11/wayland/glut/osmesa/
# vulkan disabled - no X stack, no GLUT, no Wayland. glxinfo is
# deliberately absent (needs GLX/X; Saphira ships neither).
# EGL-header note (resolved 2026-10-23): mesa-dev shipped egl.h until
# mesa r3; from mesa r4 the EGL dispatch headers live in libglvnd-dev.
# Both at once would collide on /usr/include/EGL, so the header dep is
# libglvnd-dev alone. GBM stays mesa.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Mesa validation tools: eglinfo and GLES gears (headless, no X)"
license="MIT"
origin=mesa-demos
repo=saphira
url=https://www.mesa3d.org/
source=https://archive.mesa3d.org/demos/mesa-demos-9.0.0.tar.xz
sha256=3046a3d26a7b051af7ebdd257a5f23bfeb160cad6ed952329cdff1e9f1ed496b

depends="mesa libglvnd libdrm"

makedepends="
	binutils
	gcc
	libdrm-dev
	libglvnd-dev
	meson
	ninja
	pkgconf
	python3
"

subpackages="$pkgname-doc"

recipe_build()
{
	tar --no-same-owner -C "$SRC" --strip-components=1 \
		-xf "$RECIPE_DIR/files/mesa-demos-9.0.0.tar.xz"
	# Headless: desktop GL is optional, GL-needing demos gate on its
	# presence; eglinfo (EGL-only) always builds. See files/PATCHES.md.
	patch -d "$SRC" -Np1 -i "$RECIPE_DIR/files/saphira-no-desktop-gl.patch"
	# NOTE: no comment lines inside the \-continued command below.
	meson setup "$BUILDDIR" "$SRC" \
		--prefix=/usr \
		-Dlibdir=lib \
		--buildtype=release \
		-Dx11=disabled \
		-Dwayland=disabled \
		-Dglut=disabled \
		-Dosmesa=disabled \
		-Dvulkan=disabled \
		-Degl=enabled \
		-Dgles1=enabled \
		-Dgles2=enabled \
		-Dlibdrm=enabled
	ninja -C "$BUILDDIR"
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C "$BUILDDIR" install
	# eglinfo is the package's reason to exist (headless GL proof);
	# fail closed if the patch or flags ever drop it.
	[ -x "$PKGDEST/usr/bin/eglinfo" ] ||
		{ echo "ERROR: mesa-demos staging lacks eglinfo" >&2; return 1; }
}
