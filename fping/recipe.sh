#!/bin/sh

# Parallel ping sweep tool. Installed plain 0755 with no setuid or
# capabilities, consistent with iputils/mtr in tree (modern kernels
# allow unprivileged ICMP); generations without that support run it
# via sudo like any other admin binary.

pkgname=fping
pkgver=5.5
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Parallel ping sweep tool"
# BSD-4-Clause: the Stanford COPYING keeps the advertising
# acknowledgment clause alongside non-endorsement.
license="BSD-4-Clause"
origin=fping
repo=saphira
url=https://fping.org/
source=https://github.com/schweikert/fping/archive/refs/tags/v5.5.tar.gz
sha256=e99293d31a77258b2e4a5639ff40f68db1424ce1105c3536353019e77072ba32

depends=""

makedepends="
    autoconf
    automake
    binutils
    gcc
    make
"

recipe_build()
{
	./autogen.sh
	./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
}
