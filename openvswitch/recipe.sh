#!/bin/sh

pkgname=openvswitch
pkgver=3.7.1
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Open vSwitch: production-quality multilayer virtual switch (OVS bridge dataplane for libvirt/qemu)'
license='Apache-2.0'
origin=openvswitch
repo=saphira
url=https://www.openvswitch.org/
# Vendored: https://www.openvswitch.org/releases/openvswitch-3.7.1.tar.gz
openvswitch_sha256=b8936c2e95a024d37123536ca843648bc2f1d2520921f991dd3d06248859b70f

# r0 was a legacy bootstrap build with NO depends metadata: ovs-vsctl
# failed at runtime on clean installs (libunbound.so.8, libevent-2.1.so.7
# unresolved). r1 is the native recipe with the real runtime closure.
depends="openssl zlib unbound libevent"
makedepends="
	binutils
	gawk
	gcc
	libevent-dev
	saphira-kernel-headers=7.1.5
	make
	openssl-dev
	pkgconf
	python3
	unbound-dev
	zlib-dev
"

recipe_build()
{
	OVSBALL="$RECIPE_DIR/files/openvswitch-3.7.1.tar.gz"
	echo "$openvswitch_sha256  $OVSBALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$OVSBALL"
	cd "$SRC"
	./configure --prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--with-rundir=/run/openvswitch \
		--disable-static --enable-shared --disable-libcapng
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
	rm -rf "$PKGDEST/usr/lib/systemd" "$PKGDEST/usr/lib/python"* \
		"$PKGDEST/usr/share/openvswitch/python"
	install -D -m 0644 "$RECIPE_DIR/files/openvswitch.service" \
		"$PKGDEST/usr/lib/systemd/system/openvswitch.service"
	install -D -m 0755 "$RECIPE_DIR/files/openvswitch.initd" \
		"$PKGDEST/etc/init.d/openvswitch"
	install -D -m 0644 "$RECIPE_DIR/files/openvswitch.confd" \
		"$PKGDEST/etc/conf.d/openvswitch"
	install -d -m 0755 "$PKGDEST/etc/openvswitch" "$PKGDEST/var/log/openvswitch"
}
