pkgname=rp-pppoe
pkgver=3.12
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Roaring Penguin PPPoE client, server, relay and sniffer'
license=GPL-2.0-or-later
origin=rp-pppoe
repo=saphira
url=https://github.com/Distrotech/rp-pppoe
source=https://codeload.github.com/Distrotech/rp-pppoe/tar.gz/refs/heads/master
sha256=73b189f264e345b179b1c860feb52fb7aaa3d22da5577b39fafa3086da5498d1

# Classification (dual-init audit 2026-09-03): rp-pppoe is NOT a service
# package.  Its client/server/relay helpers are invoked per configured
# session (driven by pppd); no always-on init services are invented for
# it merely to satisfy the audit.

depends="pppd dhcpcd"
makedepends="
	gawk
	binutils
	gcc
	saphira-kernel-headers=7.1.5
	make
	pppd
"

recipe_build()
{
	cd src
	./configure --prefix=/usr --enable-plugin=/usr/include
	make -j${JOBS:-$(nproc)} CFLAGS="-g -O2 -fno-strict-aliasing -Wall -Wstrict-prototypes -std=gnu99 \$(DEFINES) \$(PATHS) -Ilibevent"
}

recipe_install()
{
	install -d "$PKGDEST/usr/sbin" "$PKGDEST/etc/ppp/plugins" "$PKGDEST/etc/ppp/peers"
	for b in pppoe pppoe-server pppoe-relay pppoe-sniff; do
		install -m 755 "$SRC/src/$b" "$PKGDEST/usr/sbin/$b"
	done

	# Plugin lives in pppd's default plugin directory so the bare
	# "plugin rp-pppoe.so" lookup works; /etc/ppp/plugins keeps its
	# absolute-path compatibility entry (peers configs reference it).
	pppddir=$(basename "$(ls -d /usr/lib/pppd/*/ 2>/dev/null | head -1)")
	pppddir=${pppddir:-2.4.5}
	install -d "$PKGDEST/usr/lib/pppd/$pppddir"
	install -m 644 "$SRC/src/rp-pppoe.so" "$PKGDEST/usr/lib/pppd/$pppddir/rp-pppoe.so"
	ln -sf "/usr/lib/pppd/$pppddir/rp-pppoe.so" \
		"$PKGDEST/etc/ppp/plugins/rp-pppoe.so"

	install -m 644 "$SRC/configs/pppoe-server-options" "$PKGDEST/etc/ppp/pppoe-server-options.example"
	# Working Zen/CityFibre base config (VLAN 911). /etc is apk-protected:
	# operator-modified copies survive upgrades as pppoe.apk-new.
	install -m 644 "$RECIPE_DIR/files/peers-pppoe.example" "$PKGDEST/etc/ppp/peers/pppoe"
	install -m 644 "$RECIPE_DIR/files/dhcpcd.conf.example" "$PKGDEST/etc/dhcpcd.conf.example"
}
