#!/bin/sh
pkgname=unbound
pkgver=1.25.2
pkgrel=4
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Validating, recursive, caching DNS resolver'
license='BSD-3-Clause'
origin=unbound
repo=saphira
url=https://nlnetlabs.nl/projects/unbound/about/
unbound_sha256=0d92275c703d5f5f8baba3dab22117dd8c29b495588a5c229768ed6581566600
depends="openssl expat"
makedepends="flex bison gawk gcc make pkgconf openssl-dev expat-dev"
subpackages="$pkgname-dev $pkgname-doc"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/unbound-1.25.2.tar.gz"
	cd "$SRC"
	echo "$unbound_sha256  $RECIPE_DIR/files/unbound-1.25.2.tar.gz" | sha256sum -c -
	./configure --prefix=/usr --sysconfdir=/etc --disable-static \
		--with-pidfile=/run/unbound.pid \
		--with-rootkey-file=/usr/share/dnssec-root/trusted-key.key \
		--with-username=unbound
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
