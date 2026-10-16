#!/bin/sh

pkgname=libpq
pkgver=18.4
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="PostgreSQL C client library"
license="PostgreSQL"
origin=libpq
repo=saphira
url=https://www.postgresql.org/
source=https://ftp.postgresql.org/pub/source/v18.4/postgresql-18.4.tar.bz2
sha256=81a81ec695fb0c7901407defaa1d2f7973617154cf27ba74e3a7ab8e64436094

depends="
    libxml2
    openssl
    zlib
"

makedepends="
    binutils
    bison
    flex
    gcc
    gettext
    libxml2-dev
    make
    openssl-dev
    perl
    pkgconf
    readline-dev
    zlib-dev
"

recipe_build()
{
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	"$SRC/configure" --prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--with-openssl --with-libxml --with-zlib \
		--without-icu --without-ldap --without-pam --without-systemd \
		--without-selinux --without-llvm --without-python --without-perl \
		--without-tcl --enable-nls
	make -C src/interfaces/libpq
	make -C src/bin/pg_config
}

recipe_install()
{
	make -C "$BUILDDIR/src/interfaces/libpq" DESTDIR="$PKGDEST" install
	make -C "$BUILDDIR/src/bin/pg_config" DESTDIR="$PKGDEST" install
	# libpq-fe.h includes "postgres_ext.h" (same directory): without
	# this sibling, libpq's own public header is unusable and
	# consumers (php85 pdo_pgsql) fail. It is a static source header
	# from this same tree, not server build output.
	install -D -m 0644 "$SRC/src/include/postgres_ext.h" \
		"$PKGDEST/usr/include/postgres_ext.h"
	# libpq-fs.h is a static source header like postgres_ext.h above:
	# upstream does not install it, but php85 pdo_pgsql includes
	# <libpq/libpq-fs.h>, so place it directly in the subdir the
	# loop below creates. Not server build output.
	install -D -m 0644 "$SRC/src/include/libpq/libpq-fs.h" \
		"$PKGDEST/usr/include/libpq/libpq-fs.h"
	# php85 pdo_pgsql includes <libpq/libpq-fs.h> (upstream layout: a
	# libpq/ subdir beside the flat headers; same consumer class as
	# 74aa70d above). Mirror the installed public interface headers
	# into usr/include/libpq/ so both spellings resolve; the flat set
	# stays canonical.
	mkdir -p "$PKGDEST/usr/include/libpq"
	for h in "$PKGDEST/usr/include"/libpq-*.h \
		 "$PKGDEST/usr/include"/postgres_ext.h \
		 "$PKGDEST/usr/include"/pg_config_ext.h; do
		[ -e "$h" ] && cp -a "$h" "$PKGDEST/usr/include/libpq/"
	done
	rm -rf "$PKGDEST/usr/share/locale"
	install -D -m 0644 "$SRC/COPYRIGHT" \
		"$PKGDEST/usr/share/licenses/libpq/COPYRIGHT"
}
