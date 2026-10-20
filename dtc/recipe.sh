#!/bin/sh

pkgname=dtc
pkgver=1.8.1
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Device Tree Compiler and libfdt library (FDT support for QEMU and ARM machine models)'
license='GPL-2.0-or-later AND BSD-2-Clause'
origin=dtc
repo=saphira
url=https://www.devicetree.org/
source=https://mirrors.edge.kernel.org/pub/software/utils/dtc/dtc-1.8.1.tar.xz
sha256=23526015a6f1550e0541a53fe7acea1b5a11e3697cdf3a3bdc076abc38f6045d

depends=""
makedepends="
	binutils
	bison
	flex
	gcc
	make
	pkgconf
"

subpackages="$pkgname-dev"

# Makefile build (upstream deprecates make in favour of meson, but the
# Makefile is still shipped in 1.8.1 and is the tarball-safe path: the
# meson build uses vcs_tag(git describe) with no fallback, which fails
# in an isolated tarball build without .git. Revisit when upstream
# removes the Makefile). NO_YAML/NO_VALGRIND are automatic: Saphira
# carries neither libyaml nor valgrind, so the Makefile adds -DNO_* via
# pkg-config probes. No python/swig: pylibfdt is not packaged.
# ARFLAGS="Drc": GNU ar deterministic mode. Without it the archive
# member headers carry raw mtimes/uids/gids, so two builds of the
# identical tree produce different libfdt.a bytes (proven: two r1
# builds of this recipe differed only in the .a member metadata -
# same size, all other payload bytes identical). Deterministic
# archives keep same-NVR rebuilds byte-identical so the publisher
# never sees a spurious same-filename conflict.
recipe_build()
{
	make -C "$SRC" -j${JOBS:-$(nproc)} \
		ARFLAGS="Drc" \
		PREFIX=/usr \
		BINDIR=/usr/bin \
		LIBDIR=/usr/lib \
		INCLUDEDIR=/usr/include
}

recipe_install()
{
	make -C "$SRC" install \
		PREFIX=/usr \
		BINDIR=/usr/bin \
		LIBDIR=/usr/lib \
		INCLUDEDIR=/usr/include \
		DESTDIR="$PKGDEST"
}
