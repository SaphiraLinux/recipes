#!/bin/sh

pkgname=bind
pkgver=9.20.15
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='ISC BIND 9 nameserver (Saphira chosen DNS server: authoritative + recursive)'
license='MPL-2.0'
origin=bind
repo=saphira
url=https://www.isc.org/bind/
source=https://downloads.isc.org/isc/bind9/9.20.15/bind-9.20.15.tar.xz
sha256=d62b38fae48ba83fca6181112d0c71018d8b0f2ce285dc79dc6a0367722ccabb
# r2: default conffile is /etc/bind/named.conf (Saphira layout),
# not upstream's /etc/named.conf: no configure knob exists, so the
# two default strings are patched (daemon globals.h + check tools
# Makefile.in; rndc.key default untouched). Verified by applying to
# a scratch tree and grepping the result. Re-verify on upgrade.
# r1: initial native port from reference bind (same 9.20.15, proven
# configure set). cports pins the identical tarball sha256 above as
# independent guidance. Saphira decisions preserved from reference:
# DoH on; json-c, libidn2 and jemalloc explicitly off.

# nghttp2 ships no -dev split (single package carries lib+headers),
# so both sides name the base recipe; -dev/-doc resolution to base
# covers runtime only, not makedepends producers.
depends="libcap libuv libxml2 liblmdb nghttp2 libmaxminddb libedit ncurses openssl userspace-rcu zlib"
makedepends="gcc binutils make pkgconf perl openssl-dev libuv-dev libcap-dev libxml2-dev liblmdb nghttp2 libmaxminddb-dev libedit-dev ncurses-dev userspace-rcu-dev saphira-kernel-headers"

recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/bind-9.20.15.tar.xz" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/bind-9.20.15.tar.xz"
	cd "$SRC"
	patch -p1 < "$RECIPE_DIR/files/saphira-default-conffile.patch"
	# libuv and libcap have no configure knobs in 9.20 (mandatory,
	# pkg-config detected); the deps stay for linkage. perl builds
	# bind.keys.h via util/bindkeys.pl (build-time only).
	./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
		--with-openssl=/usr --with-maxminddb=/usr \
		--with-libnghttp2=yes --with-libxml2=yes \
		--with-lmdb=/usr --with-liburcu=membarrier --with-readline=libedit \
		--without-json-c --without-libidn2 \
		--without-jemalloc --enable-doh
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$SRC/doc/man" man
	make -C "$SRC" DESTDIR="$PKGDEST" install
	for section in 1 5 8; do
		install -d "$PKGDEST/usr/share/man/man$section"
		for page in "$SRC/doc/man"/*."$section"; do
			test -f "$page" || continue
			install -m 0644 "$page" "$PKGDEST/usr/share/man/man$section/"
		done
	done
	install -d -m 0750 "$PKGDEST/etc/bind"
	install -d -m 0750 "$PKGDEST/var/bind"
	install -D -m 0640 "$RECIPE_DIR/files/named.conf" \
		"$PKGDEST/etc/bind/named.conf"
	install -D -m 0755 "$RECIPE_DIR/files/named.initd" \
		"$PKGDEST/etc/init.d/named"
	install -D -m 0644 "$RECIPE_DIR/files/named.service" \
		"$PKGDEST/usr/lib/systemd/system/named.service"
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/bind" \
		"$PKGDEST/usr/share/saphira/accounts.d/bind"
}
