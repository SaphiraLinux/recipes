#!/bin/sh
pkgname=mawk
pkgver=1.3.4
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Fast POSIX awk (dependency-free bootstrap awk - the unblock for autotools roots)'
license='GPL-2.0-or-later'
origin=mawk
repo=saphira
url=https://invisible-island.net/mawk/
# Vendored: https://invisible-island.net/archives/mawk/mawk-1.3.4-20260302.tgz
mawk_sha256=e2c08a77d0a84a01f9be454d1ca3872d4f103f9ada683d075198b0c6e965633d
depends=""
makedepends="gcc make"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/mawk-1.3.4-20260302.tgz"
	cd "$SRC"
	echo "$mawk_sha256  $RECIPE_DIR/files/mawk-1.3.4-20260302.tgz" | sha256sum -c -
	./configure --prefix=/usr
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
	# The system expects a plain `awk`; mawk is the Saphira provider
	# (no busybox per operator policy, no gawk in clean roots).
	ln -sf mawk "$PKGDEST/usr/bin/awk"
}
