#!/bin/sh
pkgname=boost
pkgver=1.91.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Boost C++ libraries (core set: system filesystem regex thread atomic chrono date_time program_options)'
license='BSL-1.0'
origin=boost
repo=saphira
url=https://www.boost.org/
boost_sha256=5734305f40a76c30f951c9abd409a45a2a19fb546efe4162119250bbe4d3a463
depends="gcc-libs"
makedepends="gcc make python3"
subpackages="$pkgname-dev"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/boost_1_91_0.tar.gz"
	cd "$SRC"
	echo "$boost_sha256  $RECIPE_DIR/files/boost_1_91_0.tar.gz" | sha256sum -c -
	./bootstrap.sh --prefix=/usr \
		--with-libraries=filesystem,regex,thread,atomic,chrono,date_time,program_options
	./b2 -j${JOBS:-$(nproc)} \
		--prefix="$PKGDEST/usr" --libdir="$PKGDEST/usr/lib" \
		install
}
recipe_install() {
	:
}
