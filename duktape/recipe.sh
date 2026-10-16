#!/bin/sh
pkgname=duktape
pkgver=2.7.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Embeddable JavaScript engine (polkit rules dependency)'
license='MIT'
origin=duktape
repo=saphira
url=https://duktape.org/
# Upstream release dist tarball (amalgamated sources + shared-library
# makefile), not the developer git tree.
source=https://github.com/svaarala/duktape/releases/download/v2.7.0/duktape-2.7.0.tar.xz
sha256=90f8d2fa8b5567c6899830ddef2c03f3c27960b11aca222fa17aa7ac613c2890

# Single amalgamated C file; needs libm explicitly on musl (upstream
# link line carries no -lm; glibc's libm is integrated differently).
depends=""
makedepends="binutils gcc make"
subpackages="$pkgname-dev"

recipe_build() {
	DUK_BALL="$RECIPE_DIR/files/duktape-${pkgver}.tar.xz"
	echo "$sha256  $DUK_BALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$DUK_BALL"
	make -C "$SRC" -j${JOBS:-$(nproc)} -f Makefile.sharedlibrary \
		CC=gcc LDFLAGS="-lm" INSTALL_PREFIX=/usr LIBDIR=/usr/lib \
		libduktape.so.207.20700 duktape.pc
}

recipe_install() {
	install -D -m 0755 "$SRC/libduktape.so.207.20700" \
		"$PKGDEST/usr/lib/libduktape.so.207.20700"
	ln -sf libduktape.so.207.20700 "$PKGDEST/usr/lib/libduktape.so.207"
	ln -sf libduktape.so.207.20700 "$PKGDEST/usr/lib/libduktape.so"
	install -D -m 0644 "$SRC/src/duktape.h" "$PKGDEST/usr/include/duktape.h"
	install -D -m 0644 "$SRC/src/duk_config.h" \
		"$PKGDEST/usr/include/duk_config.h"
	install -D -m 0644 "$SRC/duktape.pc" \
		"$PKGDEST/usr/lib/pkgconfig/duktape.pc"
}
