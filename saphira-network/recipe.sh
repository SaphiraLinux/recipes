#!/bin/sh

pkgname=saphira-network
pkgver=0.1
pkgrel=5
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Saphira static network configuration (per-interface files, dual init system)"
license="MIT"
origin=saphira-network
repo=main
url=https://saphira.vm2.uk/

depends="
    iproute2
"

# Files-only recipe: the payload is maintained in this package tree.
# dhcpcd is used at runtime only when a config sets IPV4_MODE/IPV6_MODE
# to dhcp; OVS types additionally require openvswitch.  Long-term this
# framework supersedes the akadata-era /etc/network.d machinery; the
# tool auto-reads /etc/network.d/*.conf when /etc/saphira-network.d has
# no active configs so upgraded systems migrate without edits.

recipe_build()
{
	# Vendored payload is byte-pinned.
	(cd files && sha256sum -c ovs-vmswitch.sha256) || return 1
	# ovs-vmswitch is the SaphiraD (systemd) OVS+libvirt switch
	# provisioner; runtime deps openvswitch + libvirt are optional for
	# the base package (script checks its tools at run time).
	sh -n files/ovs-vmswitch files/ovs-lib || return 1
}

recipe_install()
{
	install -d -m 0755 "$PKGDEST/usr/sbin" \
		"$PKGDEST/etc/init.d" "$PKGDEST/usr/lib/systemd/system" \
		"$PKGDEST/etc/saphira-network.d"
	install -m 0755 "$RECIPE_DIR/files/saphira-network-config" \
		"$PKGDEST/usr/sbin/saphira-network-config"
	install -m 0644 "$RECIPE_DIR/files/saphira-network.service" \
		"$PKGDEST/usr/lib/systemd/system/saphira-network.service"
	install -m 0755 "$RECIPE_DIR/files/saphira-network.initd" \
		"$PKGDEST/etc/init.d/saphira-network"
	install -m 0755 "$RECIPE_DIR/files/ovs-vmswitch" \
		"$PKGDEST/usr/sbin/ovs-vmswitch"
	# The ovs-* do-task family (OVS_PROPOSAL.md phase 1): shared engine
	# in libexec, memorable verb commands in PATH.
	install -d -m 0755 "$PKGDEST/usr/libexec/saphira"
	install -m 0755 "$RECIPE_DIR/files/ovs-lib" \
		"$PKGDEST/usr/libexec/saphira/ovs-lib"
	for tool in ovs-bridge ovs-port ovs-uplink ovs-net ovs-status ovs-tunnel ovs-patch ovs-wan; do
		install -m 0755 "$RECIPE_DIR/files/$tool" \
			"$PKGDEST/usr/sbin/$tool"
	done
	{
		printf '# Global override: point this variable at a single file to use\n'
		printf '# it instead of the per-interface directory below.\n'
		printf '# SAPHIRA_NETWORK_CONFIG=/etc/saphira-network.conf\n'
	} > "$PKGDEST/etc/saphira-network.conf"
	install -m 0644 "$RECIPE_DIR/files/10-eth0.conf.example" \
		"$PKGDEST/etc/saphira-network.d/10-eth0.conf.example"
}
