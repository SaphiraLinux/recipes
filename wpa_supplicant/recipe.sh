#!/bin/sh

pkgname=wpa_supplicant
pkgver=2.11
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='WPA/WPA2/IEEE 802.1X supplicant (wpa_supplicant, wpa_cli, wpa_passphrase)'
license='BSD-3-Clause'
origin=wpa_supplicant
repo=saphira
url=https://w1.fi/wpa_supplicant/
source=https://w1.fi/releases/wpa_supplicant-${pkgver}.tar.gz
sha256=912ea06f74e30a8e36fbb68064d6cdff218d8d591db0fc5d75dee6c81ac7fc0a

depends="libnl openssl readline"
makedepends="
	gcc
	libnl-dev
	make
	ncurses-dev
	openssl-dev
	pkgconf
	readline-dev
"

# D-Bus control interface deliberately not enabled: keeps the dependency
# closure lean; unix-socket ctrl_iface (CONFIG_CTRL_IFACE) covers wpa_cli.
recipe_build()
{
	cd "$SRC/wpa_supplicant"
	cp defconfig .config
	sed -i -e 's|^#CONFIG_LIBNL32=y|CONFIG_LIBNL32=y|' \
		-e 's|^#CONFIG_READLINE=y|CONFIG_READLINE=y|' \
		-e 's|^CONFIG_CTRL_IFACE_DBUS_NEW=y|#&|' \
		-e 's|^CONFIG_CTRL_IFACE_DBUS_INTRO=y|#&|' \
		.config
	make -j${JOBS:-$(nproc)}

	# wpa_supplicant -v also exits nonzero (usage-style); decouple the
	# banner check from its exit status (buildpkg-single pipefail).
	./wpa_supplicant -v >"$BUILDDIR/wpa-version.txt" 2>&1 || true
	grep -q '^wpa_supplicant' "$BUILDDIR/wpa-version.txt"
	./wpa_passphrase testssid testpassphrase >"$BUILDDIR/wpa-pass.txt" 2>&1 || true
	grep -q network= "$BUILDDIR/wpa-pass.txt"
}

recipe_install()
{
	cd "$SRC/wpa_supplicant"
	for tool in wpa_supplicant wpa_cli wpa_passphrase; do
		install -D -m755 "$tool" "$PKGDEST/usr/bin/$tool"
	done
	install -D -m644 wpa_supplicant.conf \
		"$PKGDEST/usr/share/doc/wpa_supplicant/wpa_supplicant.conf"
	# Dual-init, instance-aware: the interface is always explicit
	# (systemd: wpa_supplicant@<iface> with /etc/wpa_supplicant/<iface>.conf;
	# OpenRC: rc-service wpa_supplicant.<iface>).  Nothing is
	# auto-enabled at install.
	install -d -m 0755 "$PKGDEST/etc/wpa_supplicant"
	install -D -m 0644 "$RECIPE_DIR/files/wpa_supplicant@.service" \
		"$PKGDEST/usr/lib/systemd/system/wpa_supplicant@.service"
	install -D -m 0755 "$RECIPE_DIR/files/wpa_supplicant.initd" \
		"$PKGDEST/etc/init.d/wpa_supplicant"
	test -x "$PKGDEST/usr/bin/wpa_supplicant"
	test -x "$PKGDEST/usr/bin/wpa_cli"
}
