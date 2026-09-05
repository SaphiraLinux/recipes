#!/bin/sh
pkgname=psmisc
pkgver=23.7
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Small utilities using the proc filesystem (killall, pstree, fuser)'
license='GPL-2.0-or-later'
origin=psmisc
repo=saphira
url=https://gitlab.com/psmisc/psmisc
psmisc_sha256=58c55d9c1402474065adae669511c191de374b0871eec781239ab400b907c327
depends="ncurses"
makedepends="gawk gcc make ncurses-dev"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/psmisc-23.7.tar.xz"
	cd "$SRC"
	echo "$psmisc_sha256  $RECIPE_DIR/files/psmisc-23.7.tar.xz" | sha256sum -c -
	./configure --prefix=/usr --disable-static
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
