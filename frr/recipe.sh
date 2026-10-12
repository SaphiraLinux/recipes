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
	# Dual-init policy: both definitions ship unconditionally; neither is
	# enabled or started at install.
	install -D -m 0755 "$RECIPE_DIR/files/zebra.initd" \
		"$PKGDEST/etc/init.d/zebra"
	install -D -m 0644 "$RECIPE_DIR/files/zebra.service" \
		"$PKGDEST/usr/lib/systemd/system/zebra.service"
	install -D -m 0755 "$RECIPE_DIR/files/bgpd.initd" \
		"$PKGDEST/etc/init.d/bgpd"
	install -D -m 0644 "$RECIPE_DIR/files/bgpd.service" \
		"$PKGDEST/usr/lib/systemd/system/bgpd.service"
	install -D -m 0755 "$RECIPE_DIR/files/ospfd.initd" \
		"$PKGDEST/etc/init.d/ospfd"
	install -D -m 0644 "$RECIPE_DIR/files/ospfd.service" \
		"$PKGDEST/usr/lib/systemd/system/ospfd.service"
	install -D -m 0755 "$RECIPE_DIR/files/ospf6d.initd" \
		"$PKGDEST/etc/init.d/ospf6d"
	install -D -m 0644 "$RECIPE_DIR/files/ospf6d.service" \
		"$PKGDEST/usr/lib/systemd/system/ospf6d.service"
	install -D -m 0755 "$RECIPE_DIR/files/ripd.initd" \
		"$PKGDEST/etc/init.d/ripd"
	install -D -m 0644 "$RECIPE_DIR/files/ripd.service" \
		"$PKGDEST/usr/lib/systemd/system/ripd.service"
	# Every protocol daemon needs zebra's API socket, so the unit graph
	# and the init.d depend() graph must agree.
	for d in bgpd ospfd ospf6d ripd; do
		grep -q "zebra.service" "$RECIPE_DIR/files/$d.service" || {
			echo "ERROR: frr $d.service must order after zebra.service" >&2
			return 1
		}
		grep -q "need zebra" "$RECIPE_DIR/files/$d.initd" || {
			echo "ERROR: frr $d.initd must depend on zebra" >&2
			return 1
		}
	done
	for p in etc/init.d/zebra usr/lib/systemd/system/zebra.service; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: frr payload is missing $p" >&2
			return 1
		}
	done

}
