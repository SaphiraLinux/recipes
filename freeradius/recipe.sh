#!/bin/sh

pkgname=freeradius
pkgver=3.2.10
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="RADIUS authentication, authorization and accounting server"
license="GPL-2.0-or-later"
origin=freeradius
repo=main
url=https://freeradius.org/
source=https://github.com/FreeRADIUS/freeradius-server/releases/download/release_3_2_10/freeradius-server-3.2.10.tar.gz
sha256=40e0cdfdcceb22cf0acb79bc29cf7c32995466a61fda09445ce5220608a55afd

depends="
    curl
    openssl
    pcre2
    sqlite
    talloc
"

makedepends="
    binutils
    curl-dev
    gcc
    autoconf
    automake
    libtool
    make
    openssl-dev
    pcre2-dev
    perl
    python3-dev
    sqlite-dev
    talloc-dev
"

# rlm_sql_postgresql stays disabled (no postgresql recipe); systemd off:
# Saphira uses openrc.  rlm_sql_sqlite, rlm_rest, rlm_perl and rlm_python3
# resolve against the dependencies above.
recipe_build()
{
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	autoreconf -fi "$SRC"
	"$SRC/configure" --prefix=/usr \
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
	make -C "$BUILDDIR" R="$PKGDEST" install
	rm -rf "$PKGDEST/usr/bin"
	rm -f "$PKGDEST/usr/sbin/radmin" "$PKGDEST/usr/sbin/raddebug"
	sed -i 's/^[#[:space:]]*user = radius/user = radius/' \
		"$PKGDEST/etc/raddb/radiusd.conf"
	sed -i 's/^[#[:space:]]*group = radius/group = radius/' \
		"$PKGDEST/etc/raddb/radiusd.conf"
	install -D -m 0755 "$RECIPE_DIR/files/freeradius.initd" \
		"$PKGDEST/etc/init.d/freeradius"
	install -D -m 0644 "$RECIPE_DIR/files/freeradius.service" \
		"$PKGDEST/usr/lib/systemd/system/freeradius.service"
	install -d -m 0750 "$PKGDEST/var/lib/radius" \
		"$PKGDEST/var/log/radius"
}
