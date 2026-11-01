#!/bin/sh

pkgname=postfix
pkgver=3.11.6
pkgrel=5
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Mail transfer agent (SMTP); database maps ship as optional plugins"
license="IPL-1.0 EPL-2.0 OR MPL-2.0"
origin=postfix
repo=main
url=https://www.postfix.org/
source=https://deb.debian.org/debian/pool/main/p/postfix/postfix_${pkgver}.orig.tar.gz
sha256=b9a748705b1cab0a4afcbe42f934c82a33b342ba3229017fb508c71700078d07

depends="
    openssl
    zlib
"

makedepends="
    binutils
    gawk
    gcc
    liblmdb
    libpq
    m4
    make
    mariadb-dev
    openssl-dev
    pcre2-dev
    pkgconf
    sqlite-dev
    zlib-dev
"
# gettext-dev is intentionally absent: no msgfmt/.po pipeline exists in
# this build, and nothing links libintl (musl provides gettext natively).
subpackages="postfix-sqlite postfix-mysql postfix-lmdb postfix-pgsql postfix-pcre postfix-doc"

recipe_build()
{
	# Optional databases build as dynamically-loaded plugins (one .so
	# per backend, selected by the dynamicmaps.cf.d fragments the
	# postfix-<backend> splits ship). The base daemons link no database
	# client library at all: sqlite/mysql/pgsql/lmdb/pcre only exist as
	# plugins, resolved at lookup time. DEF_DB_TYPE stays lmdb: makedefs
	# forbids hash/btree under -DNO_DB, and no other writable map type
	# exists without external libraries; the default is only consulted
	# when an operator runs postmap without an explicit type, never by
	# maildragon (all its maps name sqlite: explicitly). A missing plugin
	# fails loudly at lookup time instead of shipping silent misbehavior.
	# HAS_PCRE must carry =2 (PCRE2 API): a bare -D means 1 (PCRE1) and
	# upstream errors out; the link name is -lpcre2-8, never -lpcre2.
	make -f Makefile.init makefiles \
		shared=yes dynamicmaps=yes shlib_directory=/usr/lib/postfix \
		'CCARGS=-I/usr/include/mysql -DHAS_SQLITE -DHAS_MYSQL -DHAS_LMDB -DHAS_PCRE=2 -DHAS_PGSQL -DUSE_TLS -DNO_EAI -DNO_DB -DNO_NIS -DDEF_DB_TYPE=\"lmdb\" -DDEF_CACHE_DB_TYPE=\"lmdb\"' \
		'AUXLIBS=-lssl -lcrypto -lz -lm' \
		'AUXLIBS_SQLITE=-lsqlite3' \
		'AUXLIBS_MYSQL=-lmysqlclient' \
		'AUXLIBS_LMDB=-llmdb' \
		'AUXLIBS_PGSQL=-lpq' \
		'AUXLIBS_PCRE=-lpcre2-8'
	make
}

recipe_install()
{
	# Non-interactive installer; paths mirror the live zerodns layout.
	# mail_owner is left unset at package time so no chown to a missing
	# user can fail the build; setup provisions postfix/postdrop and the
	# main.cf template enables them.
	# Full upstream docs (man pages, html guides, README_FILES)
	# install under usr/share and ship in the postfix-doc split via
	# via the fixed -doc branch; the base package stays lightweight.
	install_root="$PKGDEST" \
	config_dir=/etc/postfix \
	daemon_directory=/usr/libexec/postfix \
	command_directory=/usr/sbin \
	queue_directory=/var/spool/postfix \
	data_directory=/var/lib/postfix \
	mail_owner= \
	setgid_group=postdrop \
	manpage_directory=/usr/share/man \
	html_directory=/usr/share/doc/postfix/html \
	readme_directory=/usr/share/doc/postfix/README_FILES \
	shlib_directory=/usr/lib/postfix \
	LD_LIBRARY_PATH="$SRC/lib" \
	sh postfix-install -non-interactive
	# shlib_directory has no usable built-in default when
	# postfix-install is invoked directly (must be absolute or
	# "no"), and the shared build's in-tree postconf needs the
	# just-built libs: this is upstream's SHLIB_ENV mechanism
	# (see `make install`), scoped to the install invocation.
	# Dual-format service package: OpenRC script and systemd unit.
	install -d -m 0755 "$PKGDEST/etc/init.d" \
		"$PKGDEST/usr/lib/systemd/system"
	install -m 0755 "$RECIPE_DIR/files/postfix.initd" \
		"$PKGDEST/etc/init.d/postfix"
	install -m 0644 "$RECIPE_DIR/files/postfix.service" \
		"$PKGDEST/usr/lib/systemd/system/postfix.service"
	# Runtime identity declaration: postfix:112 + postdrop:113 required
	# by the MTA master. makepkg generates the install scripts from
	# this fragment; the package creates its identities at install
	# time.
	# r4: fragment added (payload change, revision bumps).
	# r5: initd pidfile aligned to queue-native
	# /var/spool/postfix/pid/master.pid; stray /run/postfix
	# creation removed (payload change, revision bumps).
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/postfix" \
		"$PKGDEST/usr/share/saphira/accounts.d/postfix"
	# FHS migration declaration (hotfix/var-packaging-bug-var-run-isnot-run):
	# removal-only (no new dir: queue state stays in /var/spool).
	install -D -m 0644 "$RECIPE_DIR/files/fhs.d/postfix" \
		"$PKGDEST/usr/share/saphira/fhs.d/postfix"
	# Dynamic-maps split: base owns a backend-free dynamicmaps.cf
	# (upstream installs all 9 entries; unbuilt types would dangle).
	# Each postfix-<backend> split ships its loader fragment plus
	# its .so (see files/split-postfix-*.list). A lookup for a type
	# with no installed plugin fails loudly at lookup time.
	install -m 0644 "$RECIPE_DIR/files/dynamicmaps.cf" \
		"$PKGDEST/etc/postfix/dynamicmaps.cf"
	for backend in sqlite mysql lmdb pgsql pcre; do
		install -D -m 0644 "$RECIPE_DIR/files/dynamicmaps.d/$backend.cf" \
			"$PKGDEST/etc/postfix/dynamicmaps.cf.d/$backend.cf"
	done
}
