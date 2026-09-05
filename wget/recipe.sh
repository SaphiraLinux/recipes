#!/bin/sh
pkgname=wget
pkgver=1.25.0
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Network utility to retrieve files over HTTP/HTTPS/FTP'
license='GPL-3.0-or-later'
origin=wget
repo=saphira
url=https://www.gnu.org/software/wget/
wget_sha256=766e48423e79359ea31e41db9e5c289675947a7fcf2efdcedb726ac9d0da3784
depends="openssl zlib pcre2"
makedepends="gawk gcc make pkgconf gettext openssl-dev zlib-dev pcre2-dev"
subpackages="$pkgname-doc"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/wget-1.25.0.tar.gz"
	cd "$SRC"
	echo "$wget_sha256  $RECIPE_DIR/files/wget-1.25.0.tar.gz" | sha256sum -c -
	./configure --prefix=/usr --sysconfdir=/etc --disable-static --disable-iri --with-ssl=openssl
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
