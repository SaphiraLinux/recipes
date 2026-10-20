#!/bin/sh
pkgname=dnsmasq
pkgver=2.93
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Lightweight DNS forwarder, DHCP and TFTP server'
license='GPL-2.0-or-later'
origin=dnsmasq
repo=saphira
url=https://thekelleys.org.uk/dnsmasq/doc.html
dnsmasq_sha256=0c00d4e5c97c8306e5fb932b348b34269c9c29a0e7df0e8e82958b407092bc19
depends=""
makedepends="saphira-linux-uapi-headers gcc make"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/dnsmasq-2.93.tar.xz"
	cd "$SRC"
	echo "$dnsmasq_sha256  $RECIPE_DIR/files/dnsmasq-2.93.tar.xz" | sha256sum -c -
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" install PREFIX=/usr DESTDIR="$PKGDEST"	# Dual-init policy: both definitions ship unconditionally; neither is
	# enabled or started at install.
	install -D -m 0755 "$RECIPE_DIR/files/dnsmasq.initd" \
		"$PKGDEST/etc/init.d/dnsmasq"
	install -D -m 0644 "$RECIPE_DIR/files/dnsmasq.service" \
		"$PKGDEST/usr/lib/systemd/system/dnsmasq.service"
	install -D -m 0644 "$RECIPE_DIR/files/dnsmasq.conf.example" \
		"$PKGDEST/etc/dnsmasq.conf.example"
	# The example is shipped, never a live config: a resolver table is a
	# site decision and a wrong one silently breaks name resolution for
	# every client that trusts it.
	install -d -m 0755 "$PKGDEST/etc"
	[ -e "$PKGDEST/etc/init.d/dnsmasq" ] || { echo "ERROR: dnsmasq payload is missing etc/init.d/dnsmasq" >&2; return 1; }
	[ -e "$PKGDEST/usr/lib/systemd/system/dnsmasq.service" ] || { echo "ERROR: dnsmasq payload is missing usr/lib/systemd/system/dnsmasq.service" >&2; return 1; }
	[ -e "$PKGDEST/etc/dnsmasq.conf.example" ] || { echo "ERROR: dnsmasq payload is missing etc/dnsmasq.conf.example" >&2; return 1; }

}
