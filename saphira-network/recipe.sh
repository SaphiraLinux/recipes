#!/bin/sh

pkgname=saphira-network
pkgver=0.1
pkgrel=12
# r12: a DHCP client that cannot start must not report that it started.
# Found on a real BIOS/OpenRC image build: DHCP never worked and nothing
# said so. `dhcpcd -q <iface>` daemonises - the parent exits 0 the moment
# it forks and the privileged child dies afterwards - so the exit status
# dhcpcd_up checked was always success. On a machine whose image carried
# no `dhcpcd` account (nothing declared one anywhere in the closure) the
# child printed "no such user dhcpcd" and died, the service reported
# "configured N interface definition(s)", the boot log had nothing red in
# it, and the machine came up with no address and no default route. The
# client is now started with its own descriptors and then required to be
# alive: dhcpcd_up waits, bounded, for the pidfile the daemon writes for
# itself and fails loudly if it never appears. Proven by
# tests/dhcpcd-startup.sh.
# The configured-count is also taken from the records file rather than a
# wc -l over a printf of the variable, whose answer depended on whether
# validate_all terminates its last record - loopback plus one NIC was
# reported as "configured 1".
# r11: address-mode policy, made explicit and testable.
# SLAAC is now a first-class IPv6 mode (off|static|dhcp|slaac): the
# kernel's own IPv6 autoconfiguration via accept_ra=2 (not 1, which the
# kernel ignores while forwarding is on) and autoconf=1. SLAAC is
# IPv6-only and is never handed to dhcpcd.
# Family isolation is decided in one function (dhcpcd_plan): -4 for an
# IPv4-only DHCP selection, -6 for an IPv6-only one, neither when both
# were asked for. A family that is off, static or SLAAC is never passed
# to the client, so an explicit DHCPv6 can never imply DHCPv4 and an
# explicit DHCP can never imply SLAAC or DHCPv6.
# The resolver is now owned outright: every dhcpcd invocation carries
# -C resolv.conf. Without it the client's 20-resolv.conf hook writes
# DNS - via resolvconf(8) when present, otherwise straight to
# /etc/resolv.conf - and would silently replace the DNS servers
# firstboot recorded. The DNS choice made in firstboot is authoritative.
# Two read-only introspection verbs (mode-ok, dhcpcd-plan) answer the
# same code the service uses, so tests/network-modes.sh can assert the
# combinations without root and without a live interface.
# r10: idempotent dhcpcd start (dhcpcd_up helper): a live per-interface
# daemon owns renewals itself; a second start against an initializing
# one fails ("already running") - exactly the firstboot-apply vs
# service-start race on one file seconds apart (proven: pid 703 + ERROR
# during setup, manual rebinding fine). Skip-if-alive with a bounded
# retry for the fork handover, fail loudly past that; nothing swallowed.
# r9: systemd-networkd vendor default for wired DHCP
# (80-saphira-wired-dhcp.network, generic en*/eth* match): SaphiraD
# images boot with DHCP on any PCI slot without baking one
# predictable name and without firstboot. Inert off-networkd.
# r8: self-sufficient PATH in saphira-network-config (/usr/bin:/bin:
# /usr/sbin:/sbin at the top, not inherited from any caller - the
# systemd unit runs with a bare PATH that lacks /bin:/sbin, and the
# service died on first boot with mkdir-not-found).
# r7: depends gains findutils (saphira-network-config shells out to
# find; without it the service dies on first start - proven on the
# 0.2.1 first boot).
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Saphira static network configuration (per-interface files, dual init system)"
license="BUSL-1.1"
origin=saphira-network
repo=main
url=https://saphira.vm2.uk/

depends="
    findutils
    iproute2
"

# Files-only recipe: the payload is maintained in this package tree.
# dhcpcd is used at runtime only when a config sets IPV4_MODE/IPV6_MODE
# to dhcp; OVS types additionally require openvswitch.  Long-term this
# framework supersedes the generation-zero /etc/network.d machinery; the
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
	# systemd-networkd default wired DHCP (SaphiraD targets): generic
	# en*/eth* match so any PCI slot works without firstboot. Inert
	# everywhere networkd does not run; never contend with the
	# framework service, which systemd targets do not enable.
	install -D -m 0644 "$RECIPE_DIR/files/systemd-network/80-saphira-wired-dhcp.network" \
		"$PKGDEST/usr/lib/systemd/network/80-saphira-wired-dhcp.network"
	install -D -m 0644 "$RECIPE_DIR/files/LICENSE" \
		"$PKGDEST/usr/share/licenses/saphira-network/LICENSE"
}
