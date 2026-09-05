#!/bin/sh

pkgname=spice-server
pkgver=0.15.2
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='SPICE remote display protocol server library (spice-server for QEMU)'
license='LGPL-2.1-or-later'
origin=spice-server
repo=saphira
url=https://www.spice-space.org/
# Vendored: https://www.spice-space.org/download/releases/spice-0.15.2.tar.bz2
# Upstream 0.15+ is server-only (client lives in spice-gtk). Built
# server-side minimal: gnutls TLS, opus audio, no smartcard/sasl/
# gstreamer. pyparsing is a build-time codegen dependency (spice.proto).
spice_server_sha256=6d9eb6117f03917471c4bc10004abecff48a79fb85eb85a1c45f023377015b81

depends="glib gnutls openssl pixman lz4 libjpeg-turbo opus gcc-libs"
makedepends="
	autoconf-archive
	binutils
	gawk
	gcc
	glib-dev
	gnutls
	lz4-dev
	make
	opus-dev
	openssl-dev
	pixman-dev
	pkgconf
	python3
	pyparsing
	spice-protocol
	libjpeg-turbo
	libjpeg-turbo-dev
"

subpackages="$pkgname-dev"

recipe_build()
{
	SPBALL="$RECIPE_DIR/files/spice-0.15.2.tar.bz2"
	echo "$spice_server_sha256  $SPBALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$SPBALL"
	cd "$SRC"
	./configure --prefix=/usr \
		--disable-static \
		--enable-opus \
		--disable-smartcard \
		--without-sasl \
		--disable-gstreamer \
		--disable-manual
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
