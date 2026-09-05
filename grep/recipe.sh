#!/bin/sh
pkgname=grep
pkgver=3.12
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='GNU grep pattern searcher'
license='GPL-3.0-or-later'
origin=grep
repo=saphira
url=https://www.gnu.org/software/grep/
grep_sha256=2649b27c0e90e632eadcd757be06c6e9a4f48d941de51e7c0f83ff76408a07b9
depends="pcre2"
makedepends="gawk gcc make pcre2-dev texinfo"
recipe_build() {
	grep --version >/dev/null 2>&1 || true
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/grep-3.12.tar.xz"
	cd "$SRC"
	echo "$grep_sha256  $RECIPE_DIR/files/grep-3.12.tar.xz" | sha256sum -c -
	./configure --prefix=/usr --disable-nls
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
