#!/bin/sh
pkgname=dosfstools
pkgver=4.2
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='DOS/FAT filesystem utilities (mkfs.vfat, fsck.vfat)'
license='GPL-3.0-or-later'
origin=dosfstools
repo=saphira
url=https://github.com/dosfstools/dosfstools
dosfstools_sha256=64926eebf90092dca21b14259a5301b7b98e7b1943e8a201c7d726084809b527
depends=""
makedepends="autoconf automake gcc make"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/dosfstools-4.2.tar.gz"
	cd "$SRC"
	echo "$dosfstools_sha256  $RECIPE_DIR/files/dosfstools-4.2.tar.gz" | sha256sum -c -
	# release tarball ships pre-generated configure
	./configure --prefix=/usr --disable-static --enable-compat-symlinks
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
