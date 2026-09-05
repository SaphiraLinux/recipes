#!/bin/sh

pkgname=autoconf-archive
pkgver=2024.10.16
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Collection of freely reusable Autoconf macros'
license='GPL-3.0-or-later'
origin=autoconf-archive
repo=saphira
url=https://www.gnu.org/software/autoconf-archive/
# Vendored: https://ftp.gnu.org/gnu/autoconf-archive/autoconf-archive-2024.10.16.tar.xz
autoconf_archive_sha256=7bcd5d001916f3a50ed7436f4f700e3d2b1bade3ed803219c592d62502a57363

depends="autoconf"
makedepends="
	autoconf
	automake
	make
"

recipe_build()
{
	AABALL="$RECIPE_DIR/files/autoconf-archive-2024.10.16.tar.xz"
	echo "$autoconf_archive_sha256  $AABALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$AABALL"
	cd "$SRC"
	./configure --prefix=/usr
	make
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
