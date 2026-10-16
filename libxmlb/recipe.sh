#!/bin/sh
pkgname=libxmlb
pkgver=0.3.29
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='XML catalog library for firmware metadata (fwupd dependency)'
license='LGPL-2.1-or-later'
origin=libxmlb
repo=saphira
url=https://github.com/hughsie/libxmlb
source=https://github.com/hughsie/libxmlb/archive/refs/tags/0.3.29.tar.gz
sha256=b5efb78fc8033672826532e0e81e159dd3b01be7e8c3616e2dfefefc66d28ed6

# Stemmer stays at its upstream default (off): no libstemmer in tree
# and fwupd metadata does not need it. lzma+zstd compression explicit
# (both in tree). gtkdoc/introspection/tests off with reasons: no
# gtk-doc stack, no introspection consumers, test harness needs
# additional test-only services. xb-tool CLI ships (tiny, useful).
depends="glib xz zstd"
# Alpine-style transitive requirements for pkg-config consumers
# (xmlb.pc Requires.private liblzma+libzstd; libxslt precedent).
depends_dev="xz-dev zstd-dev"
makedepends="binutils gcc glib-dev make meson ninja pcre2-dev libffi-dev pkgconf xz-dev zlib-dev zstd-dev"
subpackages="$pkgname-dev"

recipe_build() {
	# Tag tarball vendored under URL basename (libconfuse precedent).
	XMLB_BALL="$RECIPE_DIR/files/${pkgver}.tar.gz"
	echo "$sha256  $XMLB_BALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$XMLB_BALL"
	meson setup build "$SRC" \
		--prefix=/usr \
		-Dlibdir=lib \
		-Dgtkdoc=false \
		-Dintrospection=false \
		-Dtests=false \
		-Dstemmer=false \
		-Dcli=true \
		-Dlzma=enabled \
		-Dzstd=enabled
	meson compile -C build
}

recipe_install() {
	DESTDIR="$PKGDEST" meson install -C build
	find "$PKGDEST" -name '*.a' -delete
}
