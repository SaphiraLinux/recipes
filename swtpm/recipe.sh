#!/bin/sh

pkgname=swtpm
pkgver=0.10.1
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Software TPM 2.0 emulator daemon (qemu TPM emulator backend)'
license='BSD-3-Clause'
origin=swtpm
repo=saphira
url=https://github.com/stefanberger/swtpm
# Vendored: https://github.com/stefanberger/swtpm/archive/refs/tags/v0.10.1.tar.gz
swtpm_sha256=f8da11cadfed27e26d26c5f58a7b8f2d14d684e691927348906b5891f525c684

depends="libtpms json-glib glib gnutls libseccomp openssl"
makedepends="
	autoconf
	automake
	binutils
	gawk
	gcc
	glib-dev
	gnutls-dev
	json-glib-dev
	libseccomp-dev
	libtasn1-dev
	nettle-dev
	gmp-dev
	libtool
	libtpms-dev
	saphira-kernel-headers=7.1.5
	make
	openssl-dev
	pkgconf
	python3
	socat
"

recipe_build()
{
	SWBALL="$RECIPE_DIR/files/swtpm-0.10.1.tar.gz"
	echo "$swtpm_sha256  $SWBALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$SWBALL"
	cd "$SRC"
	autoreconf -i
	./configure --prefix=/usr \
		--with-gnutls \
		--with-seccomp \
		--with-tss-user=root \
		--with-tss-group=root \
		--disable-tests
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
}
