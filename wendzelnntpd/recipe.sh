#!/bin/sh
pkgname=wendzelnntpd
pkgver=2.2.0_alpha
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="WendzelNNTPd NNTP server: IPv4/IPv6, TLS/NNTPS, AUTHINFO, ACL/RBAC (SQLite backend)"
license="GPL-3.0-or-later"
origin=wendzelnntpd
repo=saphira
url=https://github.com/cdpxe/WendzelNNTPd
# Upstream tag v2.2.0-alpha ("Bad Woerishofen", 2025-10-06). apk versions
# have no hyphen suffixes, so the apk-valid spelling is 2.2.0_alpha, which
# sorts before a future 2.2.0 final release. Selected over stable 2.1.3
# because only 2.2.x carries the native TLS connectors (NNTPS), the
# dedicated multi-listen connectors (IPv4/IPv6) and the SQLite/SQL
# injection security fixes; all features are default-on here - no
# --disable-* is passed, so no feature can be silently lost.
wendzelnntpd_sha256=8f1423d4fa39149f1bb491a24b0f9027dba87fca19e3e5f75874ed364890a217

depends="mhash openssl sqlite"
makedepends="
	bison
	flex
	gcc
	make
	mhash-dev
	openssl
	openssl-dev
	pkgconf
	sqlite
	sqlite-dev
"

recipe_build()
{
	TARBALL="$RECIPE_DIR/files/wendzelnntpd-2.2.0-alpha.tar.gz"
	echo "$wendzelnntpd_sha256  $TARBALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xzf "$TARBALL"
	cd "$SRC"
	# --disable-mysql: this package targets the SQLite backend; without
	# the switch upstream's main.h unconditionally includes
	# <mysql/mysql.h> and MySQL support is compiled in.
	./configure --prefix=/usr --sysconfdir=/etc --disable-mysql
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	# CREATE_CERTIFICATES=NO: upstream's install-time certificate
	# generation ignores DESTDIR (it reads
	# /usr/share/wendzelnntpd/openssl.cnf from the live root and writes
	# machine-specific keys into the payload). Certificates are
	# operator-owned; /usr/sbin/create_certificate still ships for the
	# operator. The SQLite database seeded by the same target is runtime
	# state too and is stripped below; the initd seeds an empty database
	# idempotently on first start instead.
	make -C "$SRC" DESTDIR="$PKGDEST" CREATE_CERTIFICATES=NO install
	# Upstream's install target also seeds certificates and the SQLite
	# database inside the payload. Both are runtime state, not package
	# payload: certificates are operator-owned (never generated at
	# package install), and a shipped usenet.db would overwrite the
	# live database on every APK upgrade (payload replacement).
	# etc/wendzelnntpd/wendzelnntpd.conf is apk protected-config and
	# survives upgrades on its own. The initd seeds an empty database
	# idempotently on first start instead.
	rm -rf "$PKGDEST/etc/wendzelnntpd/ssl"
	rm -f "$PKGDEST/var/spool/news/wendzelnntpd/usenet.db" \
		"$PKGDEST"/var/spool/news/wendzelnntpd/*.bkp \
		"$PKGDEST"/etc/wendzelnntpd/*.bkp
	install -d -m 0755 "$PKGDEST/etc/wendzelnntpd/ssl"
	install -D -m 0755 "$RECIPE_DIR/files/wendzelnntpd.initd" \
		"$PKGDEST/etc/init.d/wendzelnntpd"
	install -D -m 0644 "$RECIPE_DIR/files/wendzelnntpd.service" \
		"$PKGDEST/usr/lib/systemd/system/wendzelnntpd.service"
	# Interactive TLS setup (FQDN + optional certbot issuance) and the
	# certbot deploy hook that keeps renewed Let's Encrypt certificates
	# in /etc/wendzelnntpd/ssl in sync. Both are operator-invoked only;
	# daily certbot renewal itself is shipped by the certbot package
	# (/etc/cron.daily/certbot-renew).
	install -D -m 0755 "$RECIPE_DIR/files/wendzelnntpd-setup" \
		"$PKGDEST/usr/sbin/wendzelnntpd-setup"
	install -d -m 0755 "$PKGDEST/etc/letsencrypt/renewal-hooks/deploy"
	install -D -m 0755 "$RECIPE_DIR/files/wendzelnntpd-deploy-hook" \
		"$PKGDEST/etc/letsencrypt/renewal-hooks/deploy/wendzelnntpd"
}
