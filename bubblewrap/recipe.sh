#!/bin/sh
pkgname=bubblewrap
pkgver=0.11.2
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Unprivileged sandboxing tool (bwrap - builder prerequisite)'
license='LGPL-2.0-or-later'
origin=bubblewrap
repo=saphira
url=https://github.com/containers/bubblewrap
bubblewrap_sha256=69abc30005d2186baf7737feacd8da35633b93cf5af38838ecff17c5f8e924f6
depends="libcap"
makedepends="gawk gcc libcap-dev saphira-kernel-headers=7.1.5 make meson ninja pkgconf"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/bubblewrap-0.11.2.tar.xz"
	cd "$SRC"
	echo "$bubblewrap_sha256  $RECIPE_DIR/files/bubblewrap-0.11.2.tar.xz" | sha256sum -c -
	meson setup build . --prefix=/usr -Dlibdir=lib -Dtests=false -Dman=disabled
	meson compile -C build
}
recipe_install() {
	DESTDIR="$PKGDEST" meson install -C build
}
