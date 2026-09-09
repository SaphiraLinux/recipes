#!/bin/sh

# System stress exerciser for controlled validation runs. No dependencies
# beyond the toolchain and libc.

pkgname=stress-ng
pkgver=0.22.00
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Stress tester for system validation"
license="GPL-2.0-only"
origin=stress-ng
repo=saphira
url=https://github.com/ColinIanKing/stress-ng
source=https://github.com/ColinIanKing/stress-ng/archive/refs/tags/V0.22.00.tar.gz
sha256=4dab6440b81a05468c256e3540285d167f4b8b35f48788723f46fada3b7b71a9

depends=""

makedepends="
    binutils
    gcc
    make
"

recipe_build()
{
	make -j${JOBS:-$(nproc)} CC=gcc
}

recipe_install()
{
	make DESTDIR="$PKGDEST" BINDIR=/usr/bin MANDIR=/usr/share/man/man1 install
}
