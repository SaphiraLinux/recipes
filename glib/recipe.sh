pkgname=glib
pkgver=2.88.1
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='GLib library of C routines'
license='LGPL-2.1-or-later'
origin=glib
repo=saphira
url=https://gitlab.gnome.org/GNOME/glib
source=https://download.gnome.org/sources/glib/2.88/glib-${pkgver}.tar.xz
sha256=51ab804c56f6eab3e5045c774d1290ac5e4c923d4f9a3d8e33123bee45c1840e

depends="libffi pcre2 zlib util-linux"
# Ownership handover for the pre-split era: archive glib r1 shipped the
# headers and aclocal fragments from main. -dev takes them over on
# upgrade (manifest-level replaces covers every output; the self entry
# on main is vacuous, upgrades within a name never consult it).
replaces="glib"
subpackages="$pkgname-dev"
makedepends="gcc make pkgconf meson ninja gawk libffi-dev pcre2-dev zlib-dev util-linux-dev gettext"

recipe_build() {
	# Lean Saphira build: no tests, no docs, no introspection (needs
	# gobject-introspection), no libmount (mounted FS handling via util-linux
	# is pulled separately), no selinux, no xattr.
	meson setup build -Dtests=false -Ddocumentation=false -Dman-pages=disabled \
		-Dintrospection=disabled -Dnls=disabled -Dlibmount=disabled \
		-Dselinux=disabled -Dxattr=false --prefix=/usr
	ninja -C build
}

recipe_install() {
	DESTDIR="$PKGDEST" ninja -C build install
	# aclocal fragments belong to -dev (glib-dev owns them); the
	# automatic split does not cover usr/share/aclocal, so move them
	# explicitly - exactly one package may claim the path.
	move_staged_tree usr/share/aclocal "$pkgname-dev"
}
