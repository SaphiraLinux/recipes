#!/bin/sh

pkgname=openvswitch
pkgver=3.7.1
pkgrel=6
# r4 (never committed, unpublishable as built): fhs.d/ensure-fhs era -
# maintainer scripts called the retired helper (exit 127) and the
# rundir choice lived only in the build tree.
# r5: /var/run runtime contract (ovs daemons run from /usr, so runtime
# state belongs under /var/run; /run and /var/run are separate real
# trees, never symlinked). Commits the previously-uncommitted choice:
# --with-rundir, service/initd/tmpfiles all name /var/run/openvswitch
# (root:root 0755, as before). No accounts fragment (root service, as
# before). The old rmdir-if-empty residue line is dropped deliberately:
# /run is fresh tmpfs every boot, so volatile residue evaporates on its
# own. Payload change.
# r4 (hotfix/var-packaging-bug-var-run-isnot-run): rundir
# /run/openvswitch -> /var/run/openvswitch with the fhs.d migration
# declaration (root-run suite, no accounts.d identity; ovs-ctl owns
# lifecycle). Payload change, revision bumps.
# r6: merge line (both parents shipped different r4/r5 payloads): keep
# the r5 /var/run commitment AND the r4 fhs.d migration declaration -
# merge decision: the fhs.d migration/reconciliation machinery survives,
# so the fragment ships again. Payload change, revision bumps.
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
	saphira-linux-uapi-headers
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
		--with-rundir=/var/run/openvswitch \
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
	install -D -m 0644 "$RECIPE_DIR/files/openvswitch.tmpfiles" \
		"$PKGDEST/usr/lib/tmpfiles.d/openvswitch.conf"
	install -d -m 0755 "$PKGDEST/etc/openvswitch" "$PKGDEST/var/log/openvswitch"
	# FHS migration declaration (hotfix/var-packaging-bug-var-run-isnot-run):
	# root-run suite (no accounts.d identity); ovs-ctl owns lifecycle.
	# r4: rundir /run/openvswitch -> /var/run/openvswitch
	# (payload change, revision bumps).
	install -D -m 0644 "$RECIPE_DIR/files/fhs.d/openvswitch" \
		"$PKGDEST/usr/share/saphira/fhs.d/openvswitch"
}
