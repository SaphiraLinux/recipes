#!/bin/sh

pkgname=freeradius-clients
pkgver=3.2.10
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="FreeRADIUS client utilities (radclient, radtest, radmin, raddebug)"
license="GPL-2.0-or-later"
origin=freeradius-clients
repo=saphira
url=https://freeradius.org/
source=https://github.com/FreeRADIUS/freeradius-server/releases/download/release_3_2_10/freeradius-server-3.2.10.tar.gz
sha256=40e0cdfdcceb22cf0acb79bc29cf7c32995466a61fda09445ce5220608a55afd

depends="
    curl
    freeradius
    libpcap
    openssl
    pcre2
    readline
    sqlite
    talloc
"

makedepends="
    binutils
    curl-dev
    gcc
    autoconf
    automake
    libpcap-dev
    libtool
    make
    openssl-dev
    pcre2-dev
    perl
    python3-dev
    readline-dev
    sqlite-dev
    talloc-dev
"

# Companion unit to /recipes/freeradius (same source): the server recipe
# removes usr/bin and radmin/raddebug, which this recipe ships. The full
# build runs here too, so feature makedepends mirror the server recipe
# for what ships here (libpcap for radsniff, readline for the radclient
# CLI); r2: libpcap+readline on both dep sides.
# Runtime pin on freeradius (akadata-r0 precedent): radclient/radtest
# read their dictionaries from the server package's dictdir - a
# clients-only install without them cannot encode attributes.
# In-tree build like the server recipe (rlm_cache/configure assumes
# srcdir==builddir; VPATH fails the whole build).
recipe_build()
{
	cd "$SRC"
	autoreconf -fi .
	./configure --prefix=/usr \
		--sysconfdir=/etc --localstatedir=/var \
		--runstatedir=/run --with-raddbdir=/etc/raddb \
		--with-logdir=/var/log/radius --with-systemd=no \
		--disable-option-checking \
		--with-pcre --with-openssl \
		--without-rlm_sql_postgresql \
		--enable-reproducible-builds
	make
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
	find "$PKGDEST" -mindepth 1 -maxdepth 1 ! -name usr -exec rm -rf {} +
	find "$PKGDEST/usr" -mindepth 1 -maxdepth 1 ! -name bin ! -name sbin -exec rm -rf {} +
	find "$PKGDEST/usr/bin" -type f ! -name 'rad*' -delete
	find "$PKGDEST/usr/sbin" -type f ! -name radmin ! -name raddebug -delete
	find "$PKGDEST/usr/sbin" -type l ! -name radmin ! -name raddebug -delete
	[ -n "$(ls -A "$PKGDEST/usr/bin" 2>/dev/null)" ] ||
		{ printf 'freeradius-clients: no client binaries staged\n' >&2; exit 1; }
	install -d "$PKGDEST/usr/share/licenses/freeradius-clients"
	install -m 0644 "$SRC/LICENSE" \
		"$PKGDEST/usr/share/licenses/freeradius-clients/LICENSE"
}
