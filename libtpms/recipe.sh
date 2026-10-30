#!/bin/sh

pkgname=libtpms
pkgver=0.10.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='TPM 2.0 emulator library (swtpm backend)'
license='BSD-3-Clause'
origin=libtpms
repo=saphira
url=https://github.com/stefanberger/libtpms
# Vendored: https://github.com/stefanberger/libtpms/archive/refs/tags/v0.10.2.tar.gz
libtpms_sha256=edac03680f8a4a1c5c1d609a10e3f41e1a129e38ff5158f0c8deaedc719fb127

depends="openssl"
makedepends="
	autoconf
	automake
	bash
	binutils
	gawk
	gcc
	libtool
	saphira-linux-uapi-headers
	make
	openssl-dev
	pkgconf
"

subpackages="$pkgname-dev libtpms-doc"

recipe_build()
{
	TPBALL="$RECIPE_DIR/files/libtpms-0.10.2.tar.gz"
	echo "$libtpms_sha256  $TPBALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$TPBALL"
	cd "$SRC"
	autoreconf -i
	./configure --prefix=/usr --libdir=/usr/lib \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--with-tpm2 --with-openssl
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
