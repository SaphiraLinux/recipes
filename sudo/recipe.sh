#!/bin/sh
pkgname=sudo
pkgver=1.9.17_p2
pkgrel=4
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Give limited users limited root privileges'
license='ISC'
origin=sudo
repo=saphira
url=https://www.sudo.ws/
sudo_sha256=4a38a1ab3adb1199257edc2a7c4a2bd714665eb605b04368843b06dada2cfcfb
depends="zlib"
makedepends="zlib-dev gcc make"
subpackages="$pkgname-doc"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/sudo-1.9.17_p2.tar.gz"
	cd "$SRC"
	echo "$sudo_sha256  $RECIPE_DIR/files/sudo-1.9.17_p2.tar.gz" | sha256sum -c -
	./configure --prefix=/usr \
		--without-pam --without-sssd --without-ldap \
		--without-selinux --without-sendmail \
		--disable-nls --disable-static \
		--with-logfac=authpriv
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
	# Saphira setuid policy (hatchling sudo incident, memory note):
	# explicit 4755 so same-version reinstalls can never strip the bit.
	chmod 4755 "$PKGDEST/usr/bin/sudo" "$PKGDEST/usr/bin/sudoedit"
	ls -l "$PKGDEST/usr/bin/sudo" >&2
	stat -c "staged-mode=%a" "$PKGDEST/usr/bin/sudo" >&2
}
