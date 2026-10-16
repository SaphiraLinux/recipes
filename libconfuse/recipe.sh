#!/bin/sh
pkgname=libconfuse
pkgver=3.4
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Small configuration-file parser library (libconfuse)'
license='ISC'
origin=libconfuse
repo=saphira
url=https://github.com/libconfuse/libconfuse
# Canonical upstream moved from martinh/libconfuse to libconfuse/libconfuse;
# latest stable at packaging time is v3.4.
source=https://github.com/libconfuse/libconfuse/archive/refs/tags/v${pkgver}.tar.gz
sha256=be97bf64ab8052ef874e6c2cfabd2dacf7ad76575bb12c7c42df3fd23675d151

depends=""
# autoreconf needed: GitHub tag tarball ships no pregenerated configure.
# flex for lexer.l (no yacc parser); gettext present for the autoreconf
# toolchain, NLS disabled below so no libintl runtime dependency.
# --disable-nls keeps messages English-only and the runtime closure minimal
# (firmware-tooling support library); --disable-examples skips demo programs.
makedepends="autoconf automake binutils flex gcc gettext libtool make"
subpackages="$pkgname-dev"

recipe_build() {
	# Tag tarball is vendored under its URL basename (saphira-proxyto precedent).
	CONFUSE_BALL="$RECIPE_DIR/files/v${pkgver}.tar.gz"
	echo "$sha256  $CONFUSE_BALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$CONFUSE_BALL"
	cd "$SRC"
	autoreconf -i
	./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
		--libdir=/usr/lib --disable-static --disable-nls --disable-examples
	make -j${JOBS:-$(nproc)}
}

recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
	find "$PKGDEST" -name '*.la' -delete
}
