#!/bin/sh
pkgname=apk-tools
pkgver=3.0.5
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Alpine/saphira package manager (apk-tools 3) - Genesis base'
license='GPL-2.0-or-later'
origin=apk-tools
repo=saphira
url=https://gitlab.alpinelinux.org/alpine/apk-tools
apk_tools_sha256=8795712ce02457d29c0beb18f82851b408d1d47f98a0cbbbd33ab5ea496f665d
depends="openssl zlib"
makedepends="
	gcc
	saphira-kernel-headers=7.1.5
	make
	meson
	ninja
	openssl-dev
	pkgconf
	python3
	zlib-dev
	zstd-dev
"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/apk-tools-3.0.5.tar.gz"
	cd "$SRC"
	echo "$apk_tools_sha256  $RECIPE_DIR/files/apk-tools-3.0.5.tar.gz" | sha256sum -c -
	meson setup build . \
		--prefix=/usr \
		-Dlibdir=lib \
		-Dlua=disabled \
		-Ddocs=disabled \
		-Dtests=disabled
	meson compile -C build
}
recipe_install() {
	DESTDIR="$PKGDEST" meson install -C build
}
