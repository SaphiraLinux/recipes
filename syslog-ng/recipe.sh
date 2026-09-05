#!/bin/sh

pkgname=syslog-ng
pkgver=4.12.0
pkgrel=1
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
    glib
    json-c
    libcap
    libmaxminddb
    openssl
    pcre2
"

makedepends="
    binutils
    curl-dev
    gcc
    glib
    json-c
    libcap-dev
    libmaxminddb-dev
    make
    openssl-dev
    pcre2-dev
    pkgconf
"

# ivykis uses the vendored internal copy (no ivykis recipe in universe).
# Modules blocked on absent dependencies are explicitly disabled:
# mongodb, amqp, smtp, grpc, redis, riemann, sql, kafka, mqtt, afsnmp,
# ebpf, java.  systemd stays off: Saphira uses openrc.
recipe_build()
{
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	"$SRC/configure" --prefix=/usr \
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
	install -d -m 0755 "$PKGDEST/var/log"
}
