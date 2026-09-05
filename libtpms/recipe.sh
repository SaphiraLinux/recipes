#!/bin/sh

pkgname=libtpms
pkgver=0.10.1
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='TPM 2.0 emulator library (swtpm backend)'
license='BSD-3-Clause'
origin=libtpms
repo=saphira
url=https://github.com/stefanberger/libtpms
# Vendored: https://github.com/stefanberger/libtpms/archive/refs/tags/v0.10.1.tar.gz
libtpms_sha256=ebc24f3191d90f6cf0b4d4200cd876db4bd224b3c565708bbea0a82ee275e0fb

depends="openssl"
makedepends="
	autoconf
	automake
	bash
	binutils
	gawk
	gcc
	libtool
	saphira-kernel-headers=7.1.5
	make
	openssl-dev
	pkgconf
"

subpackages="$pkgname-dev libtpms-doc"

recipe_build()
{
	TPBALL="$RECIPE_DIR/files/libtpms-0.10.1.tar.gz"
	echo "$libtpms_sha256  $TPBALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$TPBALL"
	cd "$SRC"
	autoreconf -i
	./configure --prefix=/usr --libdir=/usr/lib \
		--with-tpm2 --with-openssl
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
