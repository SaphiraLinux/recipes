#!/bin/sh

pkgname=dovecot
pkgver=2.4.4
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="IMAP and POP3 email server"
license="LGPL-2.1-or-later MIT"
origin=dovecot
repo=main
url=https://www.dovecot.org/
source=https://dovecot.org/releases/2.4/dovecot-2.4.4.tar.gz
sha256=670f98d55a29b02ae6a97281e51374e553b94496480ab0a07439571ab30ca8c3

depends="
    bzip2
    openssl
    sqlite
    zlib
"

makedepends="
    binutils
    bzip2-dev
    gawk
    gcc
    make
    mariadb-dev
    openssl-dev
    pkgconf
    sqlite-dev
    zlib-dev
"

subpackages="
    $pkgname-dev
    $pkgname-doc
"

recipe_build()
{
	# Proven v0 flags; systemd/lua/icu/gssapi/ldap stay off, sqlite+mysql
	# on for mailDragon auth backends.  rundir matches the service files.
	./configure \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--with-ssl=openssl \
		--with-zlib \
		--without-pam --without-systemd --without-lua --without-icu \
		--without-gssapi --without-ldap \
		--with-sqlite --with-mysql \
		--with-rundir=/run/dovecot \
		--disable-static
	make
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
	install -d -m 0755 "$PKGDEST/etc/init.d" \
		"$PKGDEST/usr/lib/systemd/system" \
		"$PKGDEST/etc/dovecot" \
		"$PKGDEST/var/lib/dovecot" "$PKGDEST/var/log/dovecot"
	install -m 0644 "$RECIPE_DIR/files/dovecot.service" \
		"$PKGDEST/usr/lib/systemd/system/dovecot.service"
	install -m 0755 "$RECIPE_DIR/files/dovecot.initd" \
		"$PKGDEST/etc/init.d/dovecot"
	install -m 0644 "$RECIPE_DIR/files/dovecot.conf" \
		"$PKGDEST/etc/dovecot/dovecot.conf"
}
