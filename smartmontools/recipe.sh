#!/bin/sh
pkgname=smartmontools
pkgver=7.5
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Control and monitor storage systems with S.M.A.R.T.'
license='GPL-2.0-or-later'
origin=smartmontools
repo=saphira
url=https://www.smartmontools.org/
smartmontools_sha256=690b83ca331378da9ea0d9d61008c4b22dde391387b9bbad7f29387f2595f76e
depends="gcc-libs"
makedepends="gawk gcc make"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/smartmontools-7.5.tar.gz"
	cd "$SRC"
	echo "$smartmontools_sha256  $RECIPE_DIR/files/smartmontools-7.5.tar.gz" | sha256sum -c -
	./configure --prefix=/usr --sysconfdir=/etc --with-systemdsystemdir=/no/systemd
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
