#!/bin/sh

# Command-line editing library (knot kdig/khost/knsupdate need it;
# knot configure fails closed without it).

pkgname=libedit
pkgver=20260512-3.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Command-line editing library"
license="BSD-3-Clause"
origin=libedit
repo=saphira
url=https://www.thrysoee.dk/editline/
source=https://www.thrysoee.dk/editline/libedit-20260512-3.1.tar.gz
sha256=432d5e7ea8b0116dd39f2eca7bc11d0eed77faa6b77ea526ace89907c23ea4a0

depends=""

makedepends="
    binutils
    gcc
    make
"

subpackages="libedit-dev"

recipe_build()
{
	./configure --prefix=/usr
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
}
