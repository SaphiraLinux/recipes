#!/bin/sh

pkgname=postgresql-contrib
pkgver=18.4
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Contributed extensions shipped with PostgreSQL"
license="PostgreSQL"
origin=postgresql-contrib
repo=saphira
url=https://www.postgresql.org/
source=https://ftp.postgresql.org/pub/source/v18.4/postgresql-18.4.tar.bz2
sha256=81a81ec695fb0c7901407defaa1d2f7973617154cf27ba74e3a7ab8e64436094

depends="
    libpq
    ncurses
    postgresql-server
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

subpackages="postgresql-contrib-dev postgresql-contrib-doc"

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
	make -C "$BUILDDIR/contrib" DESTDIR="$PKGDEST" install
	rm -rf "$PKGDEST/usr/share/locale"
	install -D -m 0644 "$SRC/COPYRIGHT" \
		"$PKGDEST/usr/share/licenses/postgresql-contrib/COPYRIGHT"
}
