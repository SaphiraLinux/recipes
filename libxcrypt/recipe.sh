#!/bin/sh

pkgname=libxcrypt
pkgver=4.4.38
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Extended crypt library for password hashing (libcrypt)"
license="LGPL-2.1-or-later"
origin=libxcrypt
repo=main
url=https://github.com/besser82/libxcrypt
source=https://github.com/besser82/libxcrypt/releases/download/v4.4.38/libxcrypt-4.4.38.tar.xz
sha256=80304b9c306ea799327f01d9a7549bdb28317789182631f1b54f4511b4206dd6

depends=""
makedepends="
    binutils
    gcc
    make
    gawk
    perl
"

subpackages="$pkgname-dev libxcrypt-doc"

recipe_build()
{
	# Obsolete-API glibc compatibility stays on: consumer packages link
	# libcrypt symbols such as crypt/crypt_r directly.
	./configure \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--disable-static \
		--enable-obsolete-api=glibc \
		--disable-failure-tokens
	make
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
}
