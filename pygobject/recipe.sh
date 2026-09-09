#!/bin/sh

# Python GObject bindings (tuned's dbus/GLib mainloop path imports
# gi). Pure extension modules, no -dev split: consumers are Python,
# and pygobject.h stays with the modules.

pkgname=pygobject
pkgver=3.58.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Python GObject bindings"
license="LGPL-2.1-or-later"
origin=pygobject
repo=saphira
url=https://pygobject.gnome.org/
source=https://download.gnome.org/sources/pygobject/3.58/pygobject-3.58.0.tar.gz
sha256=45068697de3ffe46840ca369705f23118b34db4f7deb63f6eff079a6734ddcca

depends="
    glib
    gobject-introspection
    libffi
    python3
"

makedepends="
    gcc
    glib-dev
    gobject-introspection
    libffi-dev
    meson
    ninja
    pkgconf
    python3-dev
"

recipe_build()
{
	meson setup --prefix=/usr --buildtype=release "$BUILDDIR" "$SRC"
	ninja -C "$BUILDDIR" -j${JOBS:-$(nproc)}
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C "$BUILDDIR" install
}
