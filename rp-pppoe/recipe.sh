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
	saphira-kernel-headers
	make
	pppd
"

recipe_build()
{
	cd src
	./configure --prefix=/usr --sysconfdir=/etc --enable-plugin=/usr/include --localstatedir=/var
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
	#
	# The version directory is read from the merged build root, where
	# pppd is present as a declared dependency. Fail closed when it is
	# not: the previous `:-2.4.5' fallback wrote the plugin into a
	# directory pppd never scans, and wrote the /etc/ppp/plugins
	# compatibility symlink to match, so the result was a package that
	# installs cleanly and then cannot load its own plugin at runtime.
	pppddir=$(basename "$(ls -d /usr/lib/pppd/*/ 2>/dev/null | head -1)")
	if [ -z "$pppddir" ]; then
		echo "ERROR: no pppd plugin directory found under /usr/lib/pppd;" >&2
		echo "       rp-pppoe installs into the directory pppd actually" >&2
		echo "       scans, so guessing a version produces a package that" >&2
		echo "       cannot load its own plugin. Is the pppd dependency" >&2
		echo "       present in the build root?" >&2
		return 1
	fi
	install -d "$PKGDEST/usr/lib/pppd/$pppddir"
	install -m 644 "$SRC/src/rp-pppoe.so" "$PKGDEST/usr/lib/pppd/$pppddir/rp-pppoe.so"
	ln -sf "/usr/lib/pppd/$pppddir/rp-pppoe.so" \
		"$PKGDEST/etc/ppp/plugins/rp-pppoe.so"
	# The unit's ExecCondition looks for the plugin by glob, so the
	# directory we just populated is exactly what it must find.
	ls "$PKGDEST/usr/lib/pppd/"*/rp-pppoe.so >/dev/null 2>&1 || {
		echo "ERROR: rp-pppoe plugin missing from the payload" >&2
		return 1
	}

	install -m 644 "$SRC/configs/pppoe-server-options" "$PKGDEST/etc/ppp/pppoe-server-options.example"
	# Working Zen/CityFibre base config (VLAN 911). /etc is apk-protected:
	# operator-modified copies survive upgrades as pppoe.apk-new.
	install -m 644 "$RECIPE_DIR/files/peers-pppoe.example" "$PKGDEST/etc/ppp/peers/pppoe"
	install -m 644 "$RECIPE_DIR/files/dhcpcd.conf.example" "$PKGDEST/etc/dhcpcd.conf.example"
	# Dual-init policy: both definitions ship unconditionally; neither is
	# enabled or started at install.
	install -D -m 0755 "$RECIPE_DIR/files/pppoe-server.initd" \
		"$PKGDEST/etc/init.d/pppoe-server"
	install -D -m 0644 "$RECIPE_DIR/files/pppoe-server.service" \
		"$PKGDEST/usr/lib/systemd/system/pppoe-server.service"
	install -D -m 0755 "$RECIPE_DIR/files/pppoe-relay.initd" \
		"$PKGDEST/etc/init.d/pppoe-relay"
	install -D -m 0644 "$RECIPE_DIR/files/pppoe-relay.service" \
		"$PKGDEST/usr/lib/systemd/system/pppoe-relay.service"
	install -D -m 0755 "$RECIPE_DIR/files/pppoe-sniff.initd" \
		"$PKGDEST/etc/init.d/pppoe-sniff"
	install -D -m 0644 "$RECIPE_DIR/files/pppoe-sniff.service" \
		"$PKGDEST/usr/lib/systemd/system/pppoe-sniff.service"
	[ -e "$PKGDEST/etc/init.d/pppoe-server" ] || { echo "ERROR: rp-pppoe payload is missing etc/init.d/pppoe-server" >&2; return 1; }
	[ -e "$PKGDEST/usr/lib/systemd/system/pppoe-server.service" ] || { echo "ERROR: rp-pppoe payload is missing usr/lib/systemd/system/pppoe-server.service" >&2; return 1; }
	[ -e "$PKGDEST/etc/init.d/pppoe-relay" ] || { echo "ERROR: rp-pppoe payload is missing etc/init.d/pppoe-relay" >&2; return 1; }
	[ -e "$PKGDEST/usr/lib/systemd/system/pppoe-relay.service" ] || { echo "ERROR: rp-pppoe payload is missing usr/lib/systemd/system/pppoe-relay.service" >&2; return 1; }
	[ -e "$PKGDEST/etc/init.d/pppoe-sniff" ] || { echo "ERROR: rp-pppoe payload is missing etc/init.d/pppoe-sniff" >&2; return 1; }
	[ -e "$PKGDEST/usr/lib/systemd/system/pppoe-sniff.service" ] || { echo "ERROR: rp-pppoe payload is missing usr/lib/systemd/system/pppoe-sniff.service" >&2; return 1; }

}
