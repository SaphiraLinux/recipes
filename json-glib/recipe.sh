#!/bin/sh

pkgname=json-glib
pkgver=1.10.6
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='GLib JSON manipulation library (swtpm TPM profiles)'
license='LGPL-2.1-or-later'
origin=json-glib
repo=saphira
url=https://gnome.pages.gitlab.gnome.org/json-glib/
# Vendored: https://download.gnome.org/sources/json-glib/1.10/json-glib-1.10.6.tar.xz
json_glib_sha256=77f4bcbf9339528f166b8073458693f0a20b77b7059dbc2db61746a1928b0293

depends="glib"
makedepends="
	binutils
	gcc
	glib-dev
	meson
	ninja
	pkgconf
"

subpackages="$pkgname-dev"

recipe_build()
{
	JGBALL="$RECIPE_DIR/files/json-glib-1.10.6.tar.xz"
	echo "$json_glib_sha256  $JGBALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$JGBALL"
	meson setup build "$SRC" \
		--prefix=/usr \
		-Dlibdir=lib \
		-Dtests=false \
		-Dman=false
	meson compile -C build
}

recipe_install()
{
	DESTDIR="$PKGDEST" meson install -C build
}
