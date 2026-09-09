#!/bin/sh

# Kernel performance counters, locked to the default Saphira kernel
# (SAPHIRA_KERNEL_VERSION in saphira-kernel/recipe.sh, currently
# 7.2.2): perf must match the running kernel for full function, so
# this recipe moves only together with the kernel pin and its sha256
# is copied verbatim from there. Scripting/TUI stay off (NO_LIBPYTHON,
# NO_SLANG): stat/record/report/top are the deliverable; unknown make
# variables are silently ignored, so these flags fail safe.

pkgname=perf
pkgver=7.2.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Kernel performance counters (matches kernel 7.2.2)"
license="GPL-2.0-only"
origin=perf
repo=saphira
url=https://www.kernel.org/
source=https://mirrors.edge.kernel.org/pub/linux/kernel/v7.x/linux-7.2.2.tar.xz
sha256=7d0e7ce14f98c43efe880cffbf354a59be45928fdf7170d7333c374ae91c0d83

depends=""

makedepends="
    binutils
    bison
    elfutils-dev
    flex
    gcc
    make
    python3
    zlib-dev
"

recipe_build()
{
	make -C "$SRC/tools/perf" WERROR=0 NO_SLANG=1 NO_GTK2=1 \
		NO_LIBPERL=1 NO_LIBPYTHON=1 -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$SRC/tools/perf" DESTDIR="$PKGDEST" prefix=/usr install
}
