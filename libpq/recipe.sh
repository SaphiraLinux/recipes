#!/bin/sh

pkgname=libpq
pkgver=18.4
pkgrel=1
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
    pkgconf
    zlib-dev
"

recipe_build()
{
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	"$SRC/configure" --prefix=/usr \
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
	rm -rf "$PKGDEST/usr/share/locale"
	install -D -m 0644 "$SRC/COPYRIGHT" \
		"$PKGDEST/usr/share/licenses/libpq/COPYRIGHT"
}
