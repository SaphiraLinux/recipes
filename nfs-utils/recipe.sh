#!/bin/sh
pkgname=nfs-utils
pkgver=2.9.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Linux NFS userland: mount helpers, exportfs, rpc daemons (client and kernel-server stack)"
license="GPL-2.0-only AND MIT"
origin=nfs-utils
repo=saphira
url=http://nfs.sourceforge.net/
# Vendored source: https://www.kernel.org/pub/linux/utils/nfs-utils/2.9.2/nfs-utils-2.9.2.tar.xz
nfs_utils_sha256=e1dd8a9c95af15492065942cc3b52b1339ffd586baa2280ed86c9d3dc4097e8c

depends="
	keyutils
	libevent
	libnl
	libtirpc
	readline
	sqlite
"
makedepends="
	flex
	gcc
	keyutils-dev
	libevent-dev
	libnl-dev
	libtirpc-dev
	make
	pkgconf
	readline-dev
	sqlite-dev
	util-linux-dev
"

# libevent/sqlite: upstream 2.9.2 builds nfsdcld by default (operator
# decision: KEEP) but its configure.ac never sets LIBEVENT/LIBSQLITE, so
# the Makefile links them empty; the sanctioned make-variable override
# supplies the links. --disable-gss: no krb5 userspace on Saphira (kernel
# GSS support stays; mounts use sec=sys). --with-rpcgen=internal uses the
# upstream-bundled rpcgen, removing the rpcsvc-proto dependency.

recipe_build()
{
	SRCBALL="$RECIPE_DIR/files/nfs-utils-2.9.2.tar.xz"
	echo "$nfs_utils_sha256  $SRCBALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xJf "$SRCBALL"
	cd "$SRC"
	./configure --prefix=/usr --sysconfdir=/etc --sbindir=/usr/sbin \
		--disable-gss --with-rpcgen=internal
	make -j${JOBS:-$(nproc)} LIBEVENT=-levent LIBSQLITE=-lsqlite3
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install LIBEVENT=-levent LIBSQLITE=-lsqlite3
	# Operator-owned configuration (protected by apk across upgrades);
	# upstream distributes these as EXTRA_DIST and installs none of them.
	install -D -m 0644 "$SRC/nfs.conf" "$PKGDEST/etc/nfs.conf"
	install -D -m 0644 "$SRC/support/nfsidmap/idmapd.conf" \
		"$PKGDEST/etc/idmapd.conf"
	install -D -m 0644 "$SRC/utils/nfsidmap/id_resolver.conf" \
		"$PKGDEST/etc/request-key.d/id_resolver.conf"
	# Comments-only example: nothing is exported by default.
	install -D -m 0644 "$RECIPE_DIR/files/exports" "$PKGDEST/etc/exports"
	install -d -m 0755 "$PKGDEST/etc/nfs"
	# Dual init: native OpenRC + native systemd (house convention);
	# nothing auto-enables or auto-starts.
	install -D -m 0755 "$RECIPE_DIR/files/nfs-server.initd" \
		"$PKGDEST/etc/init.d/nfs-server"
	install -D -m 0755 "$RECIPE_DIR/files/nfs-client.initd" \
		"$PKGDEST/etc/init.d/nfs-client"
	install -D -m 0644 "$RECIPE_DIR/files/nfs-server.service" \
		"$PKGDEST/usr/lib/systemd/system/nfs-server.service"
	install -D -m 0644 "$RECIPE_DIR/files/nfs-client.service" \
		"$PKGDEST/usr/lib/systemd/system/nfs-client.service"
}
