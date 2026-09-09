#!/bin/sh

# Python D-Bus bindings (tuned's service-bus path imports dbus
# unconditionally). glib mainloop support comes from pygobject, not
# from here, so this stays a thin binding over libdbus.

pkgname=python-dbus
pkgver=1.4.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Python D-Bus bindings"
license="MIT"
origin=python-dbus
repo=saphira
url=https://dbus.freedesktop.org/
source=https://dbus.freedesktop.org/releases/dbus-python/dbus-python-1.4.0.tar.xz
sha256=c36b28f10ffcc8f1f798aca973bcc132f91f33eb9b6b8904381b4077766043d5

depends="
    dbus
    python3
"

makedepends="
    dbus-dev
    gcc
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
