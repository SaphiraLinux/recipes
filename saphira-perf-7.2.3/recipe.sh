#!/bin/sh

# Kernel performance counters for 7.2.3, versioned per kernel line:
# perf must match the running kernel for full function. One recipe
# directory per supported line (7.1.5, 7.2.2, 7.2.3, 7.3-rc1), each
# independently available from the repository. Like UAPI headers, perf
# installs the canonical /usr/bin/perf path, so lines are mutually
# exclusive at install time (apk refuses the dual ownership) -- that is
# inherent to single-path tools, not a defect. Scripting/TUI stay off
# (NO_LIBPYTHON, NO_SLANG): stat/record/report/top are the deliverable;
# unknown make variables are silently ignored, so these flags fail safe.

pkgname=saphira-perf-7.2.3
pkgver=1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Kernel 7.2.3 performance counters (matches kernel 7.2.3)"
license="GPL-2.0-only"
origin=saphira-perf
repo=saphira
url=https://www.kernel.org/
source=https://mirrors.edge.kernel.org/pub/linux/kernel/v7.x/linux-7.2.3.tar.xz
sha256=8ba259e8e7b13ec6ef0941c8a39ad90b24bd4a4d6c0010ba6bafb794550ecd03

depends=""

makedepends="
    binutils
    bison
    elfutils-dev
    flex
    gcc
    gettext
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
