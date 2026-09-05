#!/bin/sh

pkgname=kea
pkgver=3.0.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="ISC Kea DHCPv4, DHCPv6, DHCP-DDNS and control-agent servers"
license="MPL-2.0"
origin=kea
repo=saphira
url=https://www.isc.org/kea/
source=https://gitlab.isc.org/isc-projects/kea/-/archive/Kea-3.0.2/kea-Kea-3.0.2.tar.gz
sha256=90057889f2a147749ef4268ab970326c03c2abf66a88404c74c0a20604a4ac75

depends="
    boost
    libpq>=18.4-r1
    log4cplus>=2.1.2-r1
    mariadb>=11.8.8-r1
    openssl
"

makedepends="
    binutils
    boost-dev
    gcc
    libpq>=18.4-r1
    log4cplus-dev>=2.1.2-r1
    mariadb-dev>=11.8.8-r1
    meson
    ninja
    openssl-dev
    pkgconf
    python3
"

recipe_build()
{
	# boost 1.91+ removed BOOST_STATIC_ASSERT; use standard C++ static_assert
	find "$SRC/src" -name '*.cc' -exec sed -i \
		's/BOOST_STATIC_ASSERT(/static_assert(/g' {} +
	find "$SRC/src" -name '*.cc' -exec sed -i \
		's/boost::posix_time::millisec/boost::posix_time::milliseconds/g' {} +
	# mysql/postgresql backends enabled per feature policy (mariadb, libpq in
	# the native universe); krb5/netconf stay off (BLOCKED_BY_krb5, sysrepo).
	meson setup "$BUILDDIR" "$SRC" \
		--prefix=/usr \
		-Dlibdir=lib \
		-Drunstatedir=run \
		-Dcrypto=openssl \
		-Dkrb5=disabled -Dnetconf=disabled \
		-Dmysql=enabled -Dpostgresql=enabled \
		-Dtests=disabled -Dfuzz=disabled
	ninja -C "$BUILDDIR"
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C "$BUILDDIR" install
	# Dual-format service package: OpenRC scripts and systemd units.
	install -d -m 0755 "$PKGDEST/etc/init.d" \
		"$PKGDEST/usr/lib/systemd/system"
	for service in kea-dhcp4 kea-dhcp6 kea-dhcp-ddns kea-ctrl-agent; do
		install -m 0755 "$RECIPE_DIR/files/$service.initd" \
			"$PKGDEST/etc/init.d/$service"
		install -m 0644 "$RECIPE_DIR/files/$service.service" \
			"$PKGDEST/usr/lib/systemd/system/$service.service"
	done
}
