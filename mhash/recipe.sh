#!/bin/sh
pkgname=mhash
pkgver=0.9.9.9
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="mhash: threaded hash library (HMAC, SHA-2 family; required by wendzelnntpd)"
license="LGPL-2.0-or-later"
origin=mhash
repo=saphira
url=https://sourceforge.net/projects/mhash/
# Vendored from https://downloads.sourceforge.net/project/mhash/mhash/0.9.9.9/mhash-0.9.9.9.tar.gz
# Ported as the required password-hashing dependency of WendzelNNTPd
# (its configure hard-requires libmhash with SHA-256 support). The
# vendored patch makes the 2008-era code build under C23-default GCC and
# makes the installed headers self-contained (see the patch header for
# the full rationale, verified against the real consumer).
mhash_sha256=3dcad09a63b6f1f634e64168dd398e9feb9925560f9b671ce52283a79604d13e
subpackages="$pkgname-dev"

depends=""
makedepends="gcc make"

recipe_build()
{
	TARBALL="$RECIPE_DIR/files/mhash-0.9.9.9.tar.gz"
	echo "$mhash_sha256  $TARBALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xzf "$TARBALL"
	cd "$SRC"
	patch -p1 < "$RECIPE_DIR/files/mhash-modern-toolchain.patch"
	./configure --prefix=/usr --disable-static
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
