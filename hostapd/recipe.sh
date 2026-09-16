#!/bin/sh

pkgname=hostapd
pkgver=2.11
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='IEEE 802.11 AP, IEEE 802.1X/WPA/WPA2/EAP/RADIUS Authenticator'
license='BSD-3-Clause'
origin=hostapd
repo=saphira
url=https://w1.fi/hostapd/
source=https://w1.fi/releases/hostapd-${pkgver}.tar.gz
sha256=2b3facb632fd4f65e32f4bf82a76b4b72c501f995a4f62e330219fe7aed1747a

depends="libnl openssl"
makedepends="
    gcc
    libcap
    libnl-dev
    make
    openssl-dev
    pkgconf
"

recipe_build()
{
	cd "$SRC/hostapd"
	cp defconfig .config
	# nl80211 driver needs libnl-3; TLS via openssl; ctrl iface defaults on.
	sed -i -e 's|^#CONFIG_LIBNL32=y|CONFIG_LIBNL32=y|' \
		-e 's|^#CONFIG_IEEE80211N=y|CONFIG_IEEE80211N=y|' \
		-e 's|^#CONFIG_IEEE80211AC=y|CONFIG_IEEE80211AC=y|' \
		.config
	make -j${JOBS:-$(nproc)}

	# hostapd -v writes the banner to stderr AND exits 1 (usage-style):
	# capture with || true so pipefail does not kill the build, then
	# match the banner in the captured output.
	./hostapd -v >"$BUILDDIR/hostapd-version.txt" 2>&1 || true
	grep -q '^hostapd' "$BUILDDIR/hostapd-version.txt"
}

recipe_install()
{
	cd "$SRC/hostapd"
	install -D -m755 hostapd "$PKGDEST/usr/bin/hostapd"
	install -D -m644 hostapd.conf \
		"$PKGDEST/usr/share/doc/hostapd/hostapd.conf"
	# Dual-init, instance-aware: the interface AND its configuration are
	# always explicit (systemd: hostapd@<iface> with
	# /etc/hostapd/<iface>.conf; OpenRC: rc-service hostapd.<iface>).
	# Nothing is auto-enabled at install.
	install -d -m 0755 "$PKGDEST/etc/hostapd"
	install -D -m 0644 "$RECIPE_DIR/files/hostapd@.service" \
		"$PKGDEST/usr/lib/systemd/system/hostapd@.service"
	install -D -m 0644 "$RECIPE_DIR/files/hostapd.service" \
		"$PKGDEST/usr/lib/systemd/system/hostapd.service"
	install -D -m 0755 "$RECIPE_DIR/files/hostapd.initd" \
		"$PKGDEST/etc/init.d/hostapd"
	# Least privilege without daemon support (hostapd has no -u flag):
	# file caps for the OpenRC path (systemd uses ambient caps), so
	# the service user keeps interface config + packet injection.
	# CAP_NET_ADMIN + CAP_NET_RAW is best-effort from nl80211 needs -
	# first boot on real AP hardware proves it (fail-closed logs name
	# anything further). Unproven set, do not trim silently.
	setcap cap_net_admin,cap_net_raw+ep "$PKGDEST/usr/bin/hostapd"
	# Runtime identity declaration: hostapd:124. makepkg generates the
	# install scripts from this fragment; the package creates its
	# identity at install time. r3: identity + caps (payload changes).
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/hostapd" \
		"$PKGDEST/usr/share/saphira/accounts.d/hostapd"
	test -x "$PKGDEST/usr/bin/hostapd"
}
