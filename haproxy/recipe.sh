#!/bin/sh

pkgname=haproxy
pkgver=3.4.3
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Reliable, high performance TCP/HTTP load balancer'
license='GPL-2.0-or-later LGPL-2.1-or-later'
origin=haproxy
repo=saphira
url=https://www.haproxy.org/
source=https://www.haproxy.org/download/3.4/src/haproxy-${pkgver}.tar.gz
sha256=7fa666d36d198275999e2a68dda44d3d37960f2f7aed3a595fb811f4fd0515b5

depends="pcre2 openssl zlib"
makedepends="
	gcc
	libxcrypt-dev
	make
	openssl-dev
	pcre2-dev
	zlib-dev
"

recipe_build()
{
	make -j${JOBS:-$(nproc)} \
		TARGET=linux-musl \
		USE_GETADDRINFO=1 \
		USE_OPENSSL=1 \
		USE_PCRE2=1 \
		USE_PCRE2_JIT=1 \
		USE_PROMEX=1 \
		USE_SHM_OPEN=1 \
		USE_ZLIB=1

	./haproxy -vv | grep -qi '^HAProxy'
}

recipe_install()
{
	make DESTDIR="$PKGDEST" PREFIX=/usr SBINDIR=/usr/sbin \
		DOCDIR=/usr/share/doc/haproxy install
	install -D -m 0644 "$RECIPE_DIR/files/haproxy.cfg" \
		"$PKGDEST/etc/haproxy/haproxy.cfg"
	install -D -m 0755 "$RECIPE_DIR/files/haproxy.initd" \
		"$PKGDEST/etc/init.d/haproxy"
	install -D -m 0644 "$RECIPE_DIR/files/haproxy.service" \
		"$PKGDEST/usr/lib/systemd/system/haproxy.service"
	install -d -m 0755 "$PKGDEST/var/lib/haproxy" "$PKGDEST/var/log/haproxy"
	test -x "$PKGDEST/usr/sbin/haproxy"
}
