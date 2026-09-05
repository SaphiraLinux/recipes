#!/bin/sh
pkgname=shadow
pkgver=4.17.3
pkgrel=4
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='PAM-less password and account management tools (useradd, passwd, chage)'
license='BSD-3-Clause GPL-2.0-or-later'
origin=shadow
repo=saphira
url=https://github.com/shadow-maint/shadow
shadow_sha256=2a029091d2c2f116f51b3a817ec16e7da22310a6c8116394457483c668c84b36
depends="libxcrypt acl attr libbsd libmd"
makedepends="autoconf automake libtool gettext libxcrypt-dev acl-dev attr-dev libbsd-dev libmd-dev gcc make pkgconf"
subpackages="$pkgname-dev $pkgname-doc"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/shadow-4.17.3.tar.gz"
	cd "$SRC"
	echo "$shadow_sha256  $RECIPE_DIR/files/shadow-4.17.3.tar.gz" | sha256sum -c -
	# official release tarball ships pre-generated configure
	./configure --prefix=/usr --sysconfdir=/etc --disable-static \
		--without-libpam --without-selinux \
		--without-audit --without-subordinate-ids \
		--without-btrfs --disable-nls \
		--with-group-name-max-length=32
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
	# saphira-baselayout owns
	# /sbin/nologin; yield it until the baselayout migration replaces
	# it, otherwise every shadow upgrade collides with apk fix.
	rm -f "$PKGDEST/sbin/nologin"
	# Saphira setuid policy: explicit modes for the privileged tools.
	# makepkg preserves these bits through the rootless chown (r18).
	for tool in passwd chage chsh gpasswd newgrp; do
		[ -f "$PKGDEST/usr/bin/$tool" ] && chmod 4755 "$PKGDEST/usr/bin/$tool"
	done
}
