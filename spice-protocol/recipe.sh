#!/bin/sh

pkgname=spice-protocol
pkgver=0.14.5
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Spice protocol headers'
license='BSD-3-Clause'
origin=spice-protocol
repo=saphira
url=https://www.spice-space.org/
# Vendored: https://www.spice-space.org/download/releases/spice-protocol-0.14.5.tar.xz
spice_protocol_sha256=baf58449f6e89d19f475899ad5fb9196fdc46c03cc53233f4e39cf2978f9cff7

depends=""
makedepends="
	binutils
	gcc
	meson
	ninja
"

recipe_build()
{
	SPBALL="$RECIPE_DIR/files/spice-protocol-0.14.5.tar.xz"
	echo "$spice_protocol_sha256  $SPBALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$SPBALL"
	meson setup build "$SRC" --prefix=/usr --libdir=lib
	meson compile -C build
}

recipe_install()
{
	DESTDIR="$PKGDEST" meson install -C build
}
