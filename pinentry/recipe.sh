#!/bin/sh
pkgname=pinentry
pkgver=1.3.3
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Collection of passphrase entry dialogs (curses)'
license='GPL-2.0-or-later'
origin=pinentry
repo=saphira
url=https://www.gnupg.org/related_software/pinentry/
pinentry_sha256=c2970f16d6afb66ecddfca767d743936c86239bff936eed7fd7597a678414b63
depends="libassuan libgpg-error ncurses libcap gcc-libs"
makedepends="gawk gcc make pkgconf libassuan-dev libgpg-error-dev ncurses-dev libcap-dev"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/pinentry-1.3.3.tar.bz2"
	cd "$SRC"
	echo "$pinentry_sha256  $RECIPE_DIR/files/pinentry-1.3.3.tar.bz2" | sha256sum -c -
	# NCURSES_WIDECHAR exposes addnwstr and friends in curses.h on musl.
	CFLAGS="${CFLAGS-} -DNCURSES_WIDECHAR=1" ./configure --prefix=/usr \
		--enable-pinentry-curses --enable-fallback-curses \
		--disable-pinentry-emacs --disable-pinentry-fltk \
		--disable-pinentry-qt --disable-pinentry-tty
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
