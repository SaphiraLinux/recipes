#!/bin/sh

pkgname=saphira-network-host
pkgver=0.1
pkgrel=2
# x86_64, not noarch: see saphira-base recipe.sh (repo has no
# noarch/ payload subdir yet; same fix applies here).
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Saphira network-host group (static config framework, OVS tooling, DHCP client)'
license='BUSL-1.1'
origin=saphira-network-host
repo=saphira
url=https://saphira.vm2.uk/

# Metapackage: carries no payload of its own. The member list lives in
# depends= below and is resolved by the package manager at install
# time. Profiles and image definitions name this group; they must
# never re-enumerate its closure.
depends="
	dhcpcd
	openvswitch
	saphira-network
"
makedepends=""

recipe_build()
{
	:
}

recipe_install()
{
	install -D -m 0644 "$RECIPE_DIR/files/README.group" \
		"$PKGDEST/usr/share/doc/saphira-network-host/README.group"
	install -D -m 0644 "$RECIPE_DIR/files/LICENSE" \
		"$PKGDEST/usr/share/licenses/saphira-network-host/LICENSE"
}
