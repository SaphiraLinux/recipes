#!/bin/sh
pkgname=gnupg
pkgver=2.4.9
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='GNU Privacy Guard (complete and free implementation of OpenPGP)'
license='GPL-3.0-or-later'
origin=gnupg
repo=saphira
url=https://www.gnupg.org/
gnupg_sha256=dd17ab2e9a04fd79d39d853f599cbc852062ddb9ab52a4ddeb4176fd8b302964
depends="libassuan libgcrypt libksba npth libgpg-error zlib bzip2 readline ncurses libxcrypt pinentry sqlite"
makedepends="gawk gcc make pkgconf gettext libassuan-dev libgcrypt-dev libksba-dev npth-dev libgpg-error-dev zlib-dev bzip2-dev readline-dev ncurses-dev libxcrypt-dev"
subpackages="$pkgname-doc"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/gnupg-2.4.9.tar.bz2"
	cd "$SRC"
	echo "$gnupg_sha256  $RECIPE_DIR/files/gnupg-2.4.9.tar.bz2" | sha256sum -c -
	./configure --prefix=/usr --disable-nls --disable-ldap \
		--disable-gnutls --enable-symcryptrun
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
