#!/bin/sh

pkgname=valkey
pkgver=9.1.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Valkey: high-performance key/value datastore (Redis-compatible)"
license="BSD-3-Clause"
origin=valkey
repo=saphira
url=https://valkey.io/
source=https://github.com/valkey-io/valkey/archive/refs/tags/9.1.1.tar.gz
sha256=7d7232acd1b8a49b4e05d07a00b3ca8c801ae06ab633ca6a3423bc5f385ab7ee

makedepends="
    binutils
    gcc
    make
    openssl-dev
"

# Proven v0 build (Makefile flags preserved).
# Dual init: openrc + systemd units ship per RECIPE_RULES.md.
recipe_build()
{
	make -C "$SRC" BUILD_TLS=yes MALLOC=libc \
		CFLAGS="${CFLAGS-}" LDFLAGS="${LDFLAGS-}"
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" PREFIX=/usr install
	install -D -m 0644 "$SRC/README.md" \
		"$PKGDEST/usr/share/doc/valkey/README.md"
	install -D -m 0644 "$SRC/valkey.conf" \
		"$PKGDEST/etc/valkey/valkey.conf"
	install -d -m 0750 "$PKGDEST/var/lib/valkey" \
		"$PKGDEST/var/log/valkey"
	install -D -m 0755 "$RECIPE_DIR/files/valkey.initd" \
		"$PKGDEST/etc/init.d/valkey"
	install -D -m 0644 "$RECIPE_DIR/files/valkey.service" \
		"$PKGDEST/usr/lib/systemd/system/valkey.service"
}
