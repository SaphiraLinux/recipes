#!/bin/sh
pkgname=socat
pkgver=1.8.1.1
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Multipurpose relay (socket cat)'
license='GPL-2.0-only'
origin=socat
repo=saphira
url=http://www.dest-unreach.org/socat/
socat_sha256=f68b602c80e94b4b7498d74ec408785536fe33534b39467977a82ab2f7f01ddb
depends="openssl readline gcc-libs"
makedepends="gawk gcc make pkgconf openssl-dev readline-dev"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/socat-1.8.1.1.tar.gz"
	cd "$SRC"
	echo "$socat_sha256  $RECIPE_DIR/files/socat-1.8.1.1.tar.gz" | sha256sum -c -
	./configure --prefix=/usr --disable-static
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
