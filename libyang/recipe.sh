#!/bin/sh

# YANG data modelling library. Pinned to the v2 line: FRR 10.x builds
# against the libyang 2.x API (v3/v4/v5 are different lines - revisit
# only when FRR moves, with an explicit version error as the signal).

pkgname=libyang
pkgver=2.2.8
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="YANG data modelling library (FRR dependency)"
license="BSD-3-Clause"
origin=libyang
repo=saphira
url=https://github.com/CESNET/libyang
source=https://github.com/CESNET/libyang/archive/refs/tags/v2.2.8.tar.gz
sha256=301e134acbaa1f3eb1e5db0a996ce4bc9ff32de61c98f5fe3192e6cc84429dd3

depends="
    pcre2
"

makedepends="
    binutils
    cmake
    gcc
    make
    pcre2-dev
    pkgconf
"

subpackages="libyang-dev"

recipe_build()
{
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	cmake "$SRC" \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_BUILD_TYPE=Release
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$BUILDDIR" DESTDIR="$PKGDEST" install
}
