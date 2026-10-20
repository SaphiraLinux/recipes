#!/bin/sh

pkgname=memcached
pkgver=1.6.45
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Distributed memory object caching system (OpenStack backing service)"
license='BSD-3-Clause'
origin=memcached
repo=saphira
url=https://memcached.org/
source=https://www.memcached.org/files/memcached-1.6.45.tar.gz
sha256=d362c64e6d8d5287153501eabf7c85b4a761432fbf53f5d7b085d0bb1653c1dd

depends="
    libevent
"

makedepends="
    binutils
    gcc
    make
    pkgconf
    libevent-dev
"

# Development files ship in the main package; no -dev split.
recipe_build()
{
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	"$SRC/configure" --prefix=/usr --sysconfdir=/etc --disable-static \
		--localstatedir=/var
	make
}

recipe_install()
{
	make -C "$BUILDDIR" DESTDIR="$PKGDEST" install
	install -D -m 0755 "$RECIPE_DIR/files/memcached.initd" \
		"$PKGDEST/etc/init.d/memcached"
	install -D -m 0644 "$RECIPE_DIR/files/memcached.confd" \
		"$PKGDEST/etc/conf.d/memcached"
	install -D -m 0644 "$RECIPE_DIR/files/memcached.service" \
		"$PKGDEST/usr/lib/systemd/system/memcached.service"
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/memcached" \
		"$PKGDEST/usr/share/saphira/accounts.d/memcached"
	install -D -m 0644 "$RECIPE_DIR/files/fhs.d/memcached" \
		"$PKGDEST/usr/share/saphira/fhs.d/memcached"
	install -D -m 0644 "$SRC/COPYING" \
		"$PKGDEST/usr/share/licenses/memcached/LICENSE"
	# the daemon drops privileges itself (-u memcached, see confd);
	# the tmpfiles dir only holds the pid path
	install -D -m 0644 "$RECIPE_DIR/files/memcached.tmpfiles" \
		"$PKGDEST/usr/lib/tmpfiles.d/memcached.conf"
	for p in \
		usr/bin/memcached \
		etc/init.d/memcached \
		usr/lib/systemd/system/memcached.service \
		usr/share/saphira/accounts.d/memcached \
		usr/share/saphira/fhs.d/memcached \
	; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: memcached payload is missing $p" >&2
			return 1
		}
	done
}
