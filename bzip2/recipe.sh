#!/bin/sh
pkgname=bzip2
pkgver=1.0.8
pkgrel=5
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='High-quality block-sorting file compressor'
license='bzip2-1.0.6'
origin=bzip2
repo=saphira
url=https://www.sourceware.org/bzip2/
bzip2_sha256=ab5a03176ee106d3f0fa90e381da478ddae405918153cca248e682cd0c4a2269
depends=""
makedepends="gcc make"
subpackages="$pkgname-dev"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/bzip2-1.0.8.tar.gz"
	cd "$SRC"
	echo "$bzip2_sha256  $RECIPE_DIR/files/bzip2-1.0.8.tar.gz" | sha256sum -c -
	make -f Makefile-libbz2_so -j${JOBS:-$(nproc)}
	make -j${JOBS:-$(nproc)} libbz2.a bzip2 bzip2recover
}
recipe_install() {
	make -C "$SRC" PREFIX="$PKGDEST/usr" install
	install -m 0755 "$SRC/libbz2.so.1.0.8" "$PKGDEST/usr/lib/"
	ln -sf libbz2.so.1.0.8 "$PKGDEST/usr/lib/libbz2.so.1.0"
	ln -sf libbz2.so.1.0.8 "$PKGDEST/usr/lib/libbz2.so.1"
	ln -sf libbz2.so.1.0.8 "$PKGDEST/usr/lib/libbz2.so"
}
