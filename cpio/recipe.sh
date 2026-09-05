#!/bin/sh
pkgname=cpio
pkgver=2.15
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='GNU cpio archive utility'
license='GPL-3.0-or-later'
origin=cpio
repo=saphira
url=https://www.gnu.org/software/cpio/
cpio_sha256=efa50ef983137eefc0a02fdb51509d624b5e3295c980aa127ceee4183455499e
depends=""
makedepends="gawk gcc make"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/cpio-2.15.tar.gz"
	cd "$SRC"
	echo "$cpio_sha256  $RECIPE_DIR/files/cpio-2.15.tar.gz" | sha256sum -c -
	CFLAGS="${CFLAGS-} -std=gnu11" ./configure --prefix=/usr --disable-nls
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
