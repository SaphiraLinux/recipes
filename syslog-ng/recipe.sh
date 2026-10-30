#!/bin/sh

pkgname=syslog-ng
pkgver=4.12.0
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Enhanced system logging daemon"
license="GPL-2.0-or-later"
origin=syslog-ng
repo=saphira
url=https://www.syslog-ng.com/
source=https://github.com/syslog-ng/syslog-ng/releases/download/syslog-ng-4.12.0/syslog-ng-4.12.0.tar.gz
sha256=03a03d19ac203dca53c7ec79a7005c8a850665a95ff4cd0f1e7bb4c497c64d46

depends="
    curl
    gcc-libs
    glib
    json-c
    libcap
    libmaxminddb
    openssl
    pcre2
    python3
"

# glib alone is the runtime package and ships no pkg-config file.
# configure tests for glib-2.0, gmodule-2.0 and gthread-2.0 >= 2.32,
# and those .pc files live only in glib-dev. Without it the build
# died at configure with "Package glib-2.0 not found". The note is here
# and not inside makedepends because resolvepkg parses that string as
# a whitespace-separated dependency list and rejects a comment.
# Build-dep note: the -dev packages are not optional decoration.
# glib and json-c alone are the RUNTIME packages and ship no pkg-config
# file, so configure could not find glib-2.0, then json-c. python3 alone is
# the interpreter and ships no headers, so the Python check failed too.
# The note lives here, not inside the assignment, because resolvepkg parses
# that string as a whitespace-separated dependency list and rejects both a
# comment and an embedded double quote.
makedepends="
      binutils
      curl-dev
      gcc
      gettext
      glib
      glib-dev
      json-c
      json-c-dev
      libcap-dev
      libmaxminddb-dev
      make
      openssl-dev
      pcre2-dev
      pkgconf
      python3-dev
  "

# ivykis uses the vendored internal copy (no ivykis recipe in universe).
# Modules blocked on absent dependencies are explicitly disabled:
# mongodb, amqp, smtp, grpc, redis, riemann, sql, kafka, mqtt, afsnmp,
# ebpf, java.  systemd stays off: Saphira uses openrc.
# layout: syslog-ng's compiled default config is ${sysconfdir}/syslog-ng.conf,
# with companion patterndb.d/python beneath sysconfdir. /etc/syslog-ng keeps
# the packaged config and upstream companion data under /etc (never usr/etc);
# --localstatedir=/var keeps PID/control state out of forbidden usr/var.
recipe_build()
{
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	"$SRC/configure" --prefix=/usr \
		--sysconfdir=/etc/syslog-ng \
		--localstatedir=/var \
		--with-ivykis=internal --with-jsonc=yes --enable-json \
		--enable-http --enable-geoip2 --enable-linux-caps \
		--enable-slog --enable-python --with-python=3 \
		--disable-mongodb \
		--disable-amqp --disable-smtp --disable-grpc \
		--disable-redis --disable-riemann --disable-sql \
		--disable-kafka --disable-mqtt --disable-afsnmp \
		--disable-ebpf --disable-java --disable-java-modules \
		--disable-python-modules --disable-systemd --disable-tests
	make
}

recipe_install()
{
	make -C "$BUILDDIR" DESTDIR="$PKGDEST" install
	install -D -m 0644 "$RECIPE_DIR/files/syslog-ng.conf" \
		"$PKGDEST/etc/syslog-ng/syslog-ng.conf"
	install -D -m 0755 "$RECIPE_DIR/files/syslog-ng.initd" \
		"$PKGDEST/etc/init.d/syslog-ng"
	install -D -m 0644 "$RECIPE_DIR/files/syslog-ng.service" \
		"$PKGDEST/usr/lib/systemd/system/syslog-ng.service"
	install -D -m 0644 "$RECIPE_DIR/files/syslog-ng.tmpfiles" \
		"$PKGDEST/usr/lib/tmpfiles.d/syslog-ng.conf"
	install -d -m 0755 "$PKGDEST/var/lib/syslog-ng"
	install -d -m 0755 "$PKGDEST/var/log"
	if [ -e "$PKGDEST/usr/var" ] || [ -e "$PKGDEST/usr/etc" ]; then
		echo "syslog-ng: unexpected usr/var or usr/etc in payload" >&2
		exit 1
	fi
}
