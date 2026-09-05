#!/bin/sh

pkgname=postfix
pkgver=3.11.6
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Mail transfer agent (SMTP) with sqlite/mysql/lmdb map support"
license="IPL-1.0 EPL-2.0 OR MPL-2.0"
origin=postfix
repo=main
url=https://www.postfix.org/
source=https://deb.debian.org/debian/pool/main/p/postfix/postfix_${pkgver}.orig.tar.gz
sha256=b9a748705b1cab0a4afcbe42f934c82a33b342ba3229017fb508c71700078d07

depends="
    libmd
    sqlite
    mariadb
    openssl
    zlib
"

makedepends="
    binutils
    gawk
    gcc
    m4
    make
    mariadb-dev
    openssl-dev
    pcre2-dev
    pkgconf
    sqlite-dev
"

recipe_build()
{
	# Static inclusion of the map types mailDragon needs (sqlite first),
	# plus TLS. LMDB deferred until lmdb-dev exists in a reachable repo.
	make -f Makefile.init makefiles \
		'CCARGS=-I/usr/include/mysql -DHAS_SQLITE -DHAS_MYSQL -DUSE_TLS -DNO_EAI -DNO_DB -DNO_NIS -DDEF_DB_TYPE=\"lmdb\" -DDEF_CACHE_DB_TYPE=\"lmdb\"' \
		'AUXLIBS=-lssl -lcrypto -lz -lm -lpcre2-8' \
		'AUXLIBS_SQLITE=-lsqlite3' \
		'AUXLIBS_MYSQL=-L/usr/lib/mariadb -lmysqlclient'
	make
}

recipe_install()
{
	# Non-interactive installer; paths mirror the live zerodns layout.
	# mail_owner is left unset at package time so no chown to a missing
	# user can fail the build; setup provisions postfix/postdrop and the
	# main.cf template enables them.
	install_root="$PKGDEST" \
	config_dir=/etc/postfix \
	daemon_directory=/usr/libexec/postfix \
	command_directory=/usr/sbin \
	queue_directory=/var/spool/postfix \
	data_directory=/var/lib/postfix \
	mail_owner= \
	setgid_group=postdrop \
	manpage_directory=/usr/share/man \
	html_directory=no \
	readme_directory=no \
	sh postfix-install -non-interactive
	# Dual-format service package: OpenRC script and systemd unit.
	install -d -m 0755 "$PKGDEST/etc/init.d" \
		"$PKGDEST/usr/lib/systemd/system"
	install -m 0755 "$RECIPE_DIR/files/postfix.initd" \
		"$PKGDEST/etc/init.d/postfix"
	install -m 0644 "$RECIPE_DIR/files/postfix.service" \
		"$PKGDEST/usr/lib/systemd/system/postfix.service"
}
