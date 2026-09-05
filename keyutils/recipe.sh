#!/bin/sh
pkgname=keyutils
pkgver=1.6.3
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Linux key management utilities (kernel keyring; required for NFSv4 id mapping)"
license="GPL-2.0-or-later AND LGPL-2.0-or-later"
origin=keyutils
repo=saphira
url=https://git.kernel.org/pub/scm/linux/kernel/git/dhowells/keyutils.git/
# Vendored cgit snapshot:
# https://git.kernel.org/pub/scm/linux/kernel/git/dhowells/keyutils.git/snapshot/keyutils-1.6.3.tar.gz
keyutils_sha256=a61d5706136ae4c05bd48f86186bcfdbd88dd8bd5107e3e195c924cfc1b39bb4
subpackages="$pkgname-dev"

# Upstream Makefile has no configure; plain CFLAGS override (drops the
# built-in -Werror) is enough for musl/GCC16. Layout overrides keep the
# Saphira policy: /lib for the library, /usr/{bin,sbin} for tools.
depends=""
makedepends="gcc make"

recipe_build()
{
	TARBALL="$RECIPE_DIR/files/keyutils-1.6.3.tar.gz"
	echo "$keyutils_sha256  $TARBALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xzf "$TARBALL"
	make -C "$SRC" -j${JOBS:-$(nproc)} \
		CFLAGS="${CFLAGS-} -Wall -O2" \
		BINDIR=/usr/bin SBINDIR=/usr/sbin
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install \
		BINDIR=/usr/bin SBINDIR=/usr/sbin
}
