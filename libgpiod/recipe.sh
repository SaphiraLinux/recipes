#!/bin/sh
pkgname=libgpiod
pkgver=2.3.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Linux GPIO character-device library and command-line tools'
license='LGPL-2.1-or-later'
origin=libgpiod
repo=saphira
url=https://git.kernel.org/pub/scm/libs/libgpiod/libgpiod.git/
# C library latest at packaging time is v2.3.1 (v2.4+/v2.5 tags on
# kernel.org are the separate python-bindings lines, not the C release).
source=https://git.kernel.org/pub/scm/libs/libgpiod/libgpiod.git/snapshot/libgpiod-2.3.1.tar.gz
sha256=2e33d17f74cefadf85825f601829a68156f669348071be8470dcd700029a14af

# No runtime deps beyond libc: CLI tools talk to /dev/gpiochip* directly.
depends=""
# gpioset-interactive off: needs libedit, and only adds an interactive
# mode to gpioset (all batch tools still ship). Bindings off: no C++,
# Python, Rust or GLib consumers are packaged (dbus daemon, gobject
# introspection and systemd units out of scope with them). Man pages
# excluded deliberately: upstream generates them with help2man (not in
# tree; would drag the perl/gettext doc stack for generated pages — full
# --help text already ships in the binaries).
makedepends="
	binutils
	gcc
	saphira-kernel-headers
	meson
	ninja
	pkgconf
	make
"
subpackages="$pkgname-dev"

recipe_build() {
	GPIOD_BALL="$RECIPE_DIR/files/libgpiod-${pkgver}.tar.gz"
	echo "$sha256  $GPIOD_BALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$GPIOD_BALL"
	meson setup build "$SRC" \
		--prefix=/usr \
		-Dlibdir=lib \
		-Ddefault_library=shared \
		-Dtools=enabled \
		-Dgpioset-interactive=disabled \
		-Dtests=disabled \
		-Dexamples=disabled \
		-Dbindings-cxx=disabled \
		-Dbindings-python=disabled \
		-Dbindings-rust=disabled \
		-Dbindings-glib=disabled \
		-Ddbus=disabled \
		-Dintrospection=disabled \
		-Dsystemd=disabled
	meson compile -C build
}

recipe_install() {
	DESTDIR="$PKGDEST" meson install -C build
	# Upstream hardcodes both_libraries(); shared-only per Saphira policy.
	find "$PKGDEST" -name '*.a' -delete
}
