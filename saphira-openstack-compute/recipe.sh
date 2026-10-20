#!/bin/sh
#
# saphira-openstack-compute: OpenStack compute-node (hypervisor) role.
#
# noarch, files-only metapackage: pulls the compute closure
# (nova-compute, neutron OVS/DHCP agents, libvirt, openvswitch) and
# ships the interactive setup script that joins a bare Saphira
# machine to an existing controller as a working hypervisor.
#
# The package installs software ONLY. Nothing is configured, enabled
# or started at install time. The operator (human or agent) runs
#   saphira-openstack-setup-compute
# answers which controller to join and which NIC carries tenant
# traffic, and gets a verified hypervisor. Re-running is safe:
# existing configuration is kept unless --force is given.

pkgname=saphira-openstack-compute
pkgver=0.1
pkgrel=1
pkgarch=noarch
pkgdesc='OpenStack compute role: hypervisor services plus interactive join-a-controller setup'
license='BUSL-1.1'
origin=saphira-openstack-compute
repo=saphira
url=https://saphira.vm2.uk/

# Role closure: hypervisor daemon set, neutron agents that wire tenant
# traffic, and the installer foundation for planning primitives.
depends="
	openstack-nova
	openstack-neutron
	libvirt
	openvswitch
	dnsmasq
	iproute2
	iptables
	saphira-openstack
"
makedepends=""

recipe_build()
{
	for f in "$RECIPE_DIR"/files/setup-compute; do
		sh -n "$f" || {
			echo "ERROR: $f does not parse" >&2
			return 1
		}
	done
}

recipe_install()
{
	install -d -m 0755 "$PKGDEST/usr/sbin" \
		"$PKGDEST/usr/share/doc/saphira-openstack-compute" \
		"$PKGDEST/usr/share/licenses/saphira-openstack-compute"

	install -m 0755 "$RECIPE_DIR/files/setup-compute" \
		"$PKGDEST/usr/sbin/saphira-openstack-setup-compute"
	install -m 0644 "$RECIPE_DIR/files/README" \
		"$PKGDEST/usr/share/doc/saphira-openstack-compute/README"
	install -m 0644 "$RECIPE_DIR/files/LICENSE" \
		"$PKGDEST/usr/share/licenses/saphira-openstack-compute/LICENSE"

	for p in \
		usr/sbin/saphira-openstack-setup-compute \
		usr/share/doc/saphira-openstack-compute/README \
		usr/share/licenses/saphira-openstack-compute/LICENSE \
	; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: saphira-openstack-compute payload is missing $p" >&2
			return 1
		}
	done
	[ ! -d "$PKGDEST/etc/init.d" ] || {
		echo "ERROR: saphira-openstack-compute must not ship init units" >&2
		return 1
	}
}
