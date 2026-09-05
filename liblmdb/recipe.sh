#!/bin/sh

pkgname=liblmdb
pkgver=0.9.35
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Lightning Memory-Mapped Database (LMDB): symmetric key-value store"
license="OpenLDAP-2.8"
origin=liblmdb
repo=saphira
url=https://www.symas.com/lmdb
source=https://github.com/LMDB/lmdb/archive/refs/tags/LMDB_0.9.35.tar.gz
sha256=18b021fd589d30cc08860a9550a30ae51637117451385e9581616da751326632

makedepends="
    binutils
    gcc
    make
"

# Proven v0 build (policy exception for Makefile flags preserved).
# Development files ship in the main package; no -dev split.
recipe_build()
{
	make -C "$SRC/libraries/liblmdb" OPT= XCFLAGS="${CFLAGS-}" \
		LDFLAGS="${LDFLAGS-} -Wl,-soname,liblmdb.so.0" liblmdb.so
}

recipe_install()
{
	cd "$SRC/libraries/liblmdb"
	install -D -m 0755 liblmdb.so \
		"$PKGDEST/usr/lib/liblmdb.so.0.0.0"
	ln -s liblmdb.so.0.0.0 "$PKGDEST/usr/lib/liblmdb.so.0"
	ln -s liblmdb.so.0 "$PKGDEST/usr/lib/liblmdb.so"
	install -D -m 0644 lmdb.h "$PKGDEST/usr/include/lmdb.h"
	install -D -m 0644 LICENSE \
		"$PKGDEST/usr/share/licenses/liblmdb/LICENSE"
}
