#!/bin/sh

pkgname=dcron
pkgver=4.5
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
disabled=yes
disabled_reason='retired: cronie is the sole cron (same /usr/sbin/crond + man pages cannot coexist); cronie replaces dcron dcron-doc'
pkgdesc="Dillon's lightweight cron daemon"
license="GPL-2.0-or-later"
origin=dcron
repo=saphira
url=https://github.com/dubiousjim/dcron
source=https://github.com/dubiousjim/dcron/archive/v4.5/dcron-4.5.tar.gz
sha256=7c047194b9339b781971b000bf5512c11e856d20a14fe5323d5a1823f04c2a3f

makedepends="
    binutils
    gcc
    make
"

# Proven v0 build (Makefile flags preserved).
# Dual init: openrc + systemd units ship per RECIPE_RULES.md.
recipe_build()
{
	make -C "$SRC" PREFIX=/usr SBINDIR=/usr/sbin \
		CFLAGS="${CFLAGS-}" LDFLAGS="${LDFLAGS-}"
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" PREFIX=/usr \
		SBINDIR=/usr/sbin install
	install -D -m 0755 "$SRC/extra/run-cron" \
		"$PKGDEST/usr/sbin/run-cron"
	install -D -m 0600 "$SRC/extra/root.crontab" \
		"$PKGDEST/var/spool/cron/crontabs/root"
	install -D -m 0755 "$RECIPE_DIR/files/crond.initd" \
		"$PKGDEST/etc/init.d/crond"
	install -D -m 0644 "$RECIPE_DIR/files/crond.service" \
		"$PKGDEST/usr/lib/systemd/system/crond.service"
}
