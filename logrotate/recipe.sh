#!/bin/sh
pkgname=logrotate
pkgver=3.22.0
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Rotates, compresses, and mails system logs'
license='GPL-2.0-or-later'
origin=logrotate
repo=saphira
url=https://github.com/logrotate/logrotate
logrotate_sha256=f55b0f105f8ff145ea5b98166247d0c5d107f7fa8e8708130a2213dbde992db9
depends="popt acl attr"
makedepends="autoconf automake popt-dev acl-dev attr-dev gcc make"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/logrotate-3.22.0.tar.gz"
	cd "$SRC"
	echo "$logrotate_sha256  $RECIPE_DIR/files/logrotate-3.22.0.tar.gz" | sha256sum -c -
	autoreconf -fi
	./configure --prefix=/usr --disable-static --with-acl \
		--without-selinux --without-systemd
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
	mkdir -p "$PKGDEST/etc/logrotate.d"
}
