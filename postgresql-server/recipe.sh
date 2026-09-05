#!/bin/sh

pkgname=postgresql-server
pkgver=18.4
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="PostgreSQL database server"
license="PostgreSQL"
origin=postgresql-server
repo=saphira
url=https://www.postgresql.org/
source=https://ftp.postgresql.org/pub/source/v18.4/postgresql-18.4.tar.bz2
sha256=81a81ec695fb0c7901407defaa1d2f7973617154cf27ba74e3a7ab8e64436094

depends="
    icu
    libpq
    lz4
    ncurses
    readline
"

makedepends="
    binutils
    bison
    flex
    gcc
    gettext
    icu-dev
    libxml2-dev
    lz4-dev
    make
    ncurses-dev
    openssl-dev
    pkgconf
    readline-dev
    zlib-dev
"

subpackages="postgresql-server-dev postgresql-server-doc"

recipe_build()
{
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	"$SRC/configure" --prefix=/usr \
		--with-openssl --with-libxml --with-readline --with-zlib \
		--with-lz4 --with-icu \
		--without-ldap --without-pam --without-systemd --without-selinux \
		--without-llvm --without-python --without-perl --without-tcl \
		--enable-nls
	make world-bin
}

recipe_install()
{
	make -C "$BUILDDIR/src" DESTDIR="$PKGDEST" install
	rm -rf "$PKGDEST/usr/share/locale"
	for command in clusterdb createdb createuser dropdb dropuser pg_amcheck \
		pg_basebackup pg_combinebackup pg_dump pg_dumpall pg_isready \
		pg_receivewal pg_recvlogical pg_restore psql reindexdb vacuumdb; do
		rm -f "$PKGDEST/usr/bin/$command"
	done
	rm -f "$PKGDEST/usr/lib/libpq".* \
		"$PKGDEST/usr/lib/pkgconfig/libpq.pc" \
		"$PKGDEST/usr/bin/pg_config" \
		"$PKGDEST/usr/share/postgresql/pg_service.conf.sample"
	install -D -m 0755 "$RECIPE_DIR/files/postgresql-initdb" \
		"$PKGDEST/usr/bin/postgresql-initdb"
	install -D -m 0755 "$RECIPE_DIR/files/postgresql.initd" \
		"$PKGDEST/etc/init.d/postgresql"
	install -D -m 0644 "$RECIPE_DIR/files/postgresql.service" \
		"$PKGDEST/usr/lib/systemd/system/postgresql.service"
	install -D -m 0644 "$RECIPE_DIR/files/postgresql.confd" \
		"$PKGDEST/etc/conf.d/postgresql"
	install -D -m 0644 "$RECIPE_DIR/files/AKADATA.md" \
		"$PKGDEST/usr/share/doc/postgresql-server/AKADATA.md"
	install -d -m 0700 "$PKGDEST/var/lib/postgresql"
	install -D -m 0644 "$SRC/COPYRIGHT" \
		"$PKGDEST/usr/share/licenses/postgresql-server/COPYRIGHT"
}
