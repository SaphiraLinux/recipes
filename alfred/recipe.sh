#!/bin/sh

pkgname=alfred
pkgver=2026.3
pkgrel=3
# r3: capabilities declared (saphira-permissions V1): the
# cap_net_admin,cap_net_raw file capabilities move from a build-time
# setcap into files/caps.d/alfred, converged at install/upgrade by
# the generated ensure-caps caller (after ensure-identity and
# ensure-fhs: all three fragments now ride one package). Identity
# renumbered 104 -> 107 pre-publication: 104 belongs to the dhcpcd
# base seed (publish gate refused the collision), 107 verified free
# in TSV, tree, and ledger. Payload change, revision bumps.
# r2: unix socket /run/alfred -> /var/run/alfred via tmpfiles.d (unit
# runs unprivileged; RuntimeDirectory= cannot cover /var/run).
# Payload change, revision bumps.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Almighty Lightweight Fact Remote Exchange Daemon (batman-adv mesh information distribution)'
license='GPL-2.0-only'
origin=alfred
repo=saphira
url=https://www.open-mesh.org/projects/alfred/wiki
source=https://downloads.open-mesh.org/batman/releases/batman-adv-2026.3/alfred-2026.3.tar.gz
sha256=1f81505481aa4888e97116b374f2953aa42c25da1062984672269dc591bb0431

# Companion to batctl in the batman-adv ecosystem: the actual userspace
# daemon, distributing mesh information (hostnames, topology for
# batadv-vis) over IPv6 link-local multicast. Upstream publishes a
# detached .asc signature beside the tarball; it is archived in files/
# next to the source (recipe sha256= stays authoritative).
# Privilege model (verified in main.c): alfred retains only
# CAP_NET_ADMIN/CAP_NET_RAW via libcap, sets KEEPCAPS, then setuid()s to
# the invoking uid. It therefore runs safely as a service account when
# started with those capabilities (file caps for OpenRC, ambient caps
# for systemd) - no root daemon. GPS sharing (alfred-gpsd) is off: it
# needs libgps headers, which no Saphira package ships yet.
makedepends="
    gcc
    libcap
    libcap-dev
    libnl-dev
    make
    pkgconf
"

recipe_build()
{
	make -C "$SRC" PREFIX=/usr CONFIG_ALFRED_GPSD=n
}

recipe_install()
{
	make -C "$SRC" PREFIX=/usr DESTDIR="$PKGDEST" CONFIG_ALFRED_GPSD=n install
	# Least privilege by construction (saphira-permissions V1): the
	# binary's two capabilities (netlink query + raw multicast
	# sockets, retained across the setuid drop) are declared in
	# files/caps.d/alfred and converged at install/upgrade by the
	# generated ensure-caps caller — no build-time setcap.
	install -D -m 0644 "$RECIPE_DIR/files/caps.d/alfred" \
		"$PKGDEST/usr/share/saphira/caps.d/alfred"
	install -D -m 0644 "$SRC/README.rst" \
		"$PKGDEST/usr/share/doc/alfred/README.rst"
	install -D -m 0755 "$RECIPE_DIR/files/alfred.initd" \
		"$PKGDEST/etc/init.d/alfred"
	install -D -m 0644 "$RECIPE_DIR/files/alfred.service" \
		"$PKGDEST/usr/lib/systemd/system/alfred.service"
	install -D -m 0644 "$RECIPE_DIR/files/alfred.tmpfiles" \
		"$PKGDEST/usr/lib/tmpfiles.d/alfred.conf"
	# Runtime identity declaration: alfred:107 required by the shipped
	# service units. makepkg generates the install scripts from this
	# fragment; the package creates its identity at install time.
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/alfred" \
		"$PKGDEST/usr/share/saphira/accounts.d/alfred"
	# FHS migration declaration (hotfix/var-packaging-bug-var-run-isnot-run):
	# alfred:107 owns the corrected socket dir; makepkg runs
	# ensure-fhs after ensure-identity on install/upgrade.
	install -D -m 0644 "$RECIPE_DIR/files/fhs.d/alfred" \
		"$PKGDEST/usr/share/saphira/fhs.d/alfred"
}
