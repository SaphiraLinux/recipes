#!/bin/sh
pkgname=xfsprogs
pkgver=6.14.0
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='XFS filesystem utilities'
license='LGPL-2.1-or-later GPL-2.0-or-later'
origin=xfsprogs
repo=saphira
url=https://xfs.wiki.kernel.org/
xfsprogs_sha256=fa5ab77f8b5169ce48dd8de09446ad7e29834a05b8f52012bae411cf53ec1f58
depends="liburcu inih libaio util-linux readline"
makedepends="liburcu-dev inih-dev libaio-dev util-linux-dev readline-dev \
	gawk gcc make pkgconf saphira-kernel-headers=7.1.5 gettext"
subpackages="$pkgname-doc"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/xfsprogs-6.14.0.tar.xz"
	cd "$SRC"
	echo "$xfsprogs_sha256  $RECIPE_DIR/files/xfsprogs-6.14.0.tar.xz" | sha256sum -c -
	make configure
	./configure --prefix=/usr \
		--disable-libuuid --disable-libblkid \
		--enable-gettext=yes
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
