#!/bin/sh
pkgname=whois
pkgver=5.6.6
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Intelligent WHOIS client'
license='GPL-2.0-or-later'
origin=whois
repo=saphira
url=https://github.com/rfc1036/whois
whois_sha256=43d3b3cc64c75e8bd10aee6feff3906e9488ed335076d206e70f3b25bf644969
depends="libxcrypt"
makedepends="gcc make perl gettext libxcrypt-dev"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/whois-5.6.6.tar.gz"
	cd "$SRC"
	echo "$whois_sha256  $RECIPE_DIR/files/whois-5.6.6.tar.gz" | sha256sum -c -
	# HAVE_LIBIDN*: whois 5.5.x forbids defining these; its Makefile
	# auto-detects libidn2 (absent here) via pkg-config.
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" install BASEDIR="$PKGDEST"
}
