#!/bin/sh

pkgname=postgresql-client
pkgver=18.4
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="PostgreSQL client programs"
license="PostgreSQL"
origin=postgresql-client
repo=saphira
url=https://www.postgresql.org/
source=https://ftp.postgresql.org/pub/source/v18.4/postgresql-18.4.tar.bz2
sha256=81a81ec695fb0c7901407defaa1d2f7973617154cf27ba74e3a7ab8e64436094

depends="
    libpq
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
	make -C "$BUILDDIR" DESTDIR="$PKGDEST" install
	saved=$BUILDDIR/client/bin
	locale=$BUILDDIR/client/locale
	install -d "$saved"
	for command in clusterdb createdb createuser dropdb dropuser pg_amcheck \
		pg_basebackup pg_combinebackup pg_dump pg_dumpall pg_isready \
		pg_receivewal pg_recvlogical pg_restore psql reindexdb vacuumdb; do
		test ! -e "$PKGDEST/usr/bin/$command" || \
			cp -a "$PKGDEST/usr/bin/$command" "$saved/"
	done
	if test -d "$PKGDEST/usr/share/locale"; then
		cp -a "$PKGDEST/usr/share/locale" "$locale"
	fi
	rm -rf "$PKGDEST"/*
	install -d "$PKGDEST/usr/bin"
	cp -a "$saved"/* "$PKGDEST/usr/bin/"
	if test -d "$locale"; then
		install -d "$PKGDEST/usr/share"
		cp -a "$locale" "$PKGDEST/usr/share/"
	fi
	install -D -m 0644 "$SRC/COPYRIGHT" \
		"$PKGDEST/usr/share/licenses/postgresql-client/COPYRIGHT"
}
