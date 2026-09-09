#!/bin/sh

# FRR routing suite (RIP/RIPv2/RIPng/OSPF/OSPFv3/BGP and the rest via
# zebra). Quagga is the old lineage and is deliberately not packaged;
# BIRD stays out to avoid overlap. Default daemon set (no trimming
# flags): fewer custom knobs, unknown --enable/--disable spellings
# only warn under autoconf. SNMP/docs follow upstream defaults.

pkgname=frr
pkgver=10.7.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="FRRouting suite (RIP/OSPF/BGP)"
license="GPL-2.0-or-later"
origin=frr
repo=saphira
url=https://frrouting.org/
source=https://github.com/FRRouting/frr/archive/refs/tags/frr-10.7.1.tar.gz
sha256=6aaf9d89deb94eeda6acceaa6fe48d8cd365d0908231e58f628538ff49696fc4

depends="
    json-c
    libyang
    openssl
    readline
"

makedepends="
    autoconf
    automake
    binutils
    gcc
    json-c-dev
    libtool
    libyang-dev
    make
    openssl-dev
    pkgconf
    python3
    readline-dev
"

recipe_build()
{
	./bootstrap.sh
	./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
		--enable-user=frr --enable-group=frr --enable-vtysh
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
	install -d -m 0755 "$PKGDEST/etc/frr"
	# Runtime identity declaration: frr:125 for the routing daemons
	# (matches --enable-user/--enable-group) and the PID/state dir.
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/frr" \
		"$PKGDEST/usr/share/saphira/accounts.d/frr"
}
