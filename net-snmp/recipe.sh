#!/bin/sh

pkgname=net-snmp
pkgver=5.9.5.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Net-SNMP tools, agent and trap daemon (snmpwalk, snmpd, snmptrapd, ...)'
license='BSD-3-Clause'
origin=net-snmp
repo=saphira
url=https://www.net-snmp.org/
source=https://downloads.sourceforge.net/project/net-snmp/net-snmp/5.9.5.2/net-snmp-5.9.5.2.tar.gz
sha256=16707719f833184a4b72835dac359ae188123b06b5e42817c00790d7dc1384bf

# Full toolset build: agent (snmpd), trap daemon (snmptrapd), all CLI
# tools, MIBs and manuals. No feature --disable-* flags: perl and python
# bindings stay at configure defaults against the repo perl/python3-dev.
# License is the CMU/UCD BSD-like family (see COPYING parts 1-2).
subpackages="$pkgname-dev $pkgname-doc"
depends="openssl"
makedepends="
    gcc
    libcap
    make
    openssl-dev
    perl
    pkgconf
    python3-dev
"

recipe_build()
{
	cd "$SRC"
	./configure \
		--prefix=/usr \
		--sysconfdir=/etc \
		--mandir=/usr/share/man \
		--localstatedir=/var \
		--with-default-snmp-version=3 \
		--with-persistent-directory=/var/lib/snmp
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	cd "$SRC"
	make DESTDIR="$PKGDEST" install
	# Least privilege by construction: both daemons drop to the snmp
	# account via -u/-g, but must bind ports 161/162 (<1024). The file
	# capability carries that single privilege; both service units
	# additionally start them as snmp outright.
	setcap cap_net_bind_service+ep "$PKGDEST/usr/sbin/snmpd"
	setcap cap_net_bind_service+ep "$PKGDEST/usr/sbin/snmptrapd"
	# Saphira default configs: local monitoring only. The admin opens
	# wider access deliberately by editing these files.
	install -D -m 0644 "$RECIPE_DIR/files/snmpd.conf" \
		"$PKGDEST/etc/snmp/snmpd.conf"
	install -D -m 0644 "$RECIPE_DIR/files/snmptrapd.conf" \
		"$PKGDEST/etc/snmp/snmptrapd.conf"
	install -d -m 0750 "$PKGDEST/var/lib/snmp"
	install -D -m 0755 "$RECIPE_DIR/files/snmpd.initd" \
		"$PKGDEST/etc/init.d/snmpd"
	install -D -m 0755 "$RECIPE_DIR/files/snmptrapd.initd" \
		"$PKGDEST/etc/init.d/snmptrapd"
	install -D -m 0644 "$RECIPE_DIR/files/snmpd.service" \
		"$PKGDEST/usr/lib/systemd/system/snmpd.service"
	install -D -m 0644 "$RECIPE_DIR/files/snmptrapd.service" \
		"$PKGDEST/usr/lib/systemd/system/snmptrapd.service"
	# Runtime identity declaration: snmp:105 required by the shipped
	# service units. makepkg generates the install scripts from this
	# fragment; the package creates its identity at install time.
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/snmp" \
		"$PKGDEST/usr/share/saphira/accounts.d/snmp"
}
