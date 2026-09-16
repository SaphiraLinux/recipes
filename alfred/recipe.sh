#!/bin/sh

pkgname=alfred
pkgver=2026.3
pkgrel=1
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
	make -C "$SRC" PREFIX=/usr DESTDIR="$PKGDEST" install
	# Least privilege by construction: the binary carries only the two
	# capabilities alfred retains across its setuid drop (netlink query
	# + raw multicast sockets). Both service units start it as alfred.
	setcap cap_net_admin,cap_net_raw+ep "$PKGDEST/usr/sbin/alfred"
	install -D -m 0644 "$SRC/README.rst" \
		"$PKGDEST/usr/share/doc/alfred/README.rst"
	install -D -m 0755 "$RECIPE_DIR/files/alfred.initd" \
		"$PKGDEST/etc/init.d/alfred"
	install -D -m 0644 "$RECIPE_DIR/files/alfred.service" \
		"$PKGDEST/usr/lib/systemd/system/alfred.service"
	# Runtime identity declaration: alfred:104 required by the shipped
	# service units. makepkg generates the install scripts from this
	# fragment; the package creates its identity at install time.
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/alfred" \
		"$PKGDEST/usr/share/saphira/accounts.d/alfred"
}
