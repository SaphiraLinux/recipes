#!/bin/sh

pkgname=getent
pkgver=1.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Look up entries in local passwd/group/shadow files"
license="MIT"
origin=getent
repo=main
url=https://saphira.vm2.uk/

depends=""

makedepends="
    gcc
"

recipe_build()
{
	# No configure step: a single C source compiled directly against the
	# generation-zero musl headers. Reads the credential files as they are.
	gcc ${CFLAGS-} -static -Os -s -o getent "$RECIPE_DIR/files/getent.c"
}

recipe_install()
{
	install -D -m 0755 getent "$PKGDEST/usr/bin/getent"
}
