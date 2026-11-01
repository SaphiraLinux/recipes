#!/bin/sh

# GObject introspection (pygobject backend for tuned's dbus/GLib
# integration). .gir XML stays in the main package next to the
# .typelib binaries; only C headers split to -dev.

pkgname=gobject-introspection
pkgver=1.86.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="GObject introspection (pygobject backend)"
license="GPL-2.0-or-later LGPL-2.1-or-later"
origin=gobject-introspection
repo=saphira
url=https://gi.readthedocs.io/
source=https://download.gnome.org/sources/gobject-introspection/1.86/gobject-introspection-1.86.0.tar.xz
sha256=920d1a3fcedeadc32acff95c2e203b319039dd4b4a08dd1a2dfd283d19c0b9ae

depends="
    glib
"

makedepends="
    binutils
    gcc
    glib-dev
    libffi-dev
    meson
    ninja
    pcre2-dev
    pkgconf
    python3-dev
    setuptools
"
# setuptools: meson probes the python3 module (python3-dev ships no
# setuptools); provider package is named `setuptools`.
# pcre2-dev: glib-2.0.pc Requires libpcre2-8 (meson-log evidence).
# libffi-dev: gobject-2.0.pc Requires libffi (meson-log evidence).

subpackages="gobject-introspection-dev"

recipe_build()
{
	meson setup --prefix=/usr --buildtype=release "$BUILDDIR" "$SRC"
	ninja -C "$BUILDDIR" -j${JOBS:-$(nproc)}
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C "$BUILDDIR" install
}
