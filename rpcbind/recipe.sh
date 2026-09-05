#!/bin/sh
pkgname=rpcbind
pkgver=1.2.9
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Portmap replacement for ONC RPC (required for NFSv3 and other RPC services)"
license="BSD-3-Clause"
origin=rpcbind
repo=saphira
url=https://sourceforge.net/projects/rpcbind/
# Vendored source: https://downloads.sourceforge.net/project/rpcbind/rpcbind/1.2.9/rpcbind-1.2.9.tar.bz2
rpcbind_sha256=ce5f1a87c566ef0b2897a28f50a75c1dc23fec413a46a7f4183423b6b6aa991b

depends="libtirpc"
makedepends="
	gcc
	make
	libtirpc-dev
	pkgconf
"

recipe_build()
{
	SRCBALL="$RECIPE_DIR/files/rpcbind-1.2.9.tar.bz2"
	echo "$rpcbind_sha256  $SRCBALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xjf "$SRCBALL"
	cd "$SRC"
	# musl has no sys/queue.h (glibc-ism). rpcbind's configure.ac
	# CLOBBERS CPPFLAGS (CPPFLAGS=$TIRPC_CFLAGS, then CPPFLAGS=), so an
	# env/include-path fix is discarded. Instead place the vendored BSD
	# queue.h (reused from the libtirpc port's queue-compat) at
	# $SRC/sys/queue.h - the automake compile lines carry -I. over the
	# source root, so <sys/queue.h> resolves without touching flags.
	# --with-systemdsystemunitdir=no: upstream's default queries
	# pkg-config for the systemd unit dir; without systemd.pc the empty
	# result is not "no", so configure enters the libsystemd check and
	# errors out. The house unit is packaged instead (files/rpcbind.service).
	mkdir -p "$SRC/sys"
	cp "$RECIPE_DIR/files/queue-compat/sys/queue.h" "$SRC/sys/queue.h"
	./configure --prefix=/usr --sbindir=/usr/sbin \
		--with-systemdsystemunitdir=no
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
}
