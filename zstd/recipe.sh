#!/bin/sh
pkgname=zstd
pkgver=1.5.7
pkgrel=4
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Zstandard real-time compression'
license='BSD-3-Clause AND GPL-2.0-or-later'
origin=zstd
repo=saphira
url=https://facebook.github.io/zstd/
zstd_sha256=eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3
depends=""
makedepends="gcc make"
subpackages="$pkgname-dev"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/zstd-1.5.7.tar.gz"
	make -C "$SRC" -j${JOBS:-$(nproc)} PREFIX=/usr ZSTD_LEGACY_SUPPORT=0 CC=gcc
}
recipe_install() {
	make -C "$SRC" install PREFIX=/usr DESTDIR="$PKGDEST" ZSTD_LEGACY_SUPPORT=0 CC=gcc
	# FHS non-usrmerged: /bin|/sbin consumers need the runtime SONAME
	# chain in /lib; the dev linker name stays in /usr/lib pointing
	# back (acl precedent).
	mkdir -p "$PKGDEST/lib"
	for lib in "$PKGDEST/usr/lib/libzstd.so.1"*; do
		[ -e "$lib" ] && mv "$lib" "$PKGDEST/lib/"
	done
	link="$PKGDEST/usr/lib/libzstd.so"
	if [ -L "$link" ]; then
		target=$(readlink "$link")
		case $target in */*) :;; *) [ -e "$PKGDEST/lib/$target" ] && ln -sf "../../lib/$target" "$link";; esac
	fi
}
