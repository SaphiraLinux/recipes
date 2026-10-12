pkgname=libvirt
pkgver=12.6.0
pkgrel=6
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Libvirt control plane: modular daemons (virtqemud/storaged/networkd/nodedevd/secretd/logd/lockd, virtproxyd TLS entry), virsh, QEMU/network/storage drivers (headless, no GUI)'
license='LGPL-2.1-or-later'
origin=libvirt
repo=saphira
url=https://libvirt.org/
# Vendored: https://download.libvirt.org/libvirt-12.6.0.tar.xz
libvirt_sha256=1592256deb76fc94028ff083a4d9f06a74f3b92a66a1794f37bc26f21430c888

# libpciaccess is a RUNTIME dep: libvirt_driver_nodedev.so needs
# libpciaccess.so.0 (r2 shipped it only as a makedepend and failed at
# daemon start on clean installs).
depends="glib libnl libxml2 readline zlib curl openssl libtirpc gnutls json-c libbsd libxcrypt acl attr udev dnsmasq qemu dmidecode nettle libtasn1 libunistring libpciaccess iproute2 nftables"
makedepends="
	acl-dev
	binutils
	curl-dev
	gawk
	gcc
	gnutls
	nettle-dev
	glib-dev
	libnl-dev
	libtirpc
	libxml2-dev
	json-c
	libpciaccess
	libxcrypt-dev
	make
	meson
	ninja
	pkgconf
	python3
	libxslt
	perl
	readline-dev
	udev-dev
	zlib-dev
"

# Modular daemons from day one: no monolithic libvirtd dependency over
# the architecture. virtqemud/virtstoraged/virtnetworkd/virtnodedevd/
# virtsecretd do the work, virtlogd/virtlockd assist, virtproxyd is the
# remote TLS entry point (certs are deployment config, not packaging).
# Upstream ships the OpenRC init scripts (-Dinit_script=openrc installs
# one per enabled daemon, with VIRT*_OPTS conf.d hooks and reload), so
# no hand init files. storage_dir/storage_fs stay at defaults (enabled)
# so Gluster FUSE mounts slot in as plain dir/fs pools; storage_gluster
# (libgfapi) stays disabled - that QEMU backend is dead upstream and
# nothing here may depend on it. remote_default_mode=direct is the
# modular-correct client routing (qemu:///system -> virtqemud socket).
# No polkit/dbus/audit/selinux, no GUI, nwfilter+libpcap deferred.
recipe_build()
{
	LVBALL="$RECIPE_DIR/files/libvirt-12.6.0.tar.xz"
	echo "$libvirt_sha256  $LVBALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$LVBALL"
	patch -Np1 -i "$RECIPE_DIR/files/0001-secret-init-use-bin-sh-non-usrmerged.patch"
	meson setup build "$SRC" --prefix=/usr \
		-Dpackager=Saphira \
		-Ddocs=disabled -Dtests=disabled \
		-Dlibvirtd=disabled -Dremote_default_mode=direct \
		-Ddriver_qemu=enabled -Ddriver_network=enabled \
		-Ddriver_secrets=enabled \
		-Ddriver_lxc=disabled -Ddriver_libxl=disabled \
		-Ddriver_bhyve=disabled -Ddriver_esx=disabled \
		-Ddriver_hyperv=disabled -Ddriver_vz=disabled \
		-Ddriver_vbox=disabled \
		-Dqemu_user=root -Dqemu_group=root \
		-Dpolkit=disabled -Dselinux=disabled -Dapparmor=disabled \
		-Daudit=disabled -Dnumactl=disabled -Dcapng=disabled \
		-Dsanlock=disabled -Dglusterfs=disabled -Dlibiscsi=disabled \
		-Dfuse=disabled -Dlibssh=disabled -Dnetcf=disabled \
		-Dopenwsman=disabled -Dfirewalld=disabled -Dfirewalld_zone=disabled \
		-Dstorage_gluster=disabled -Dstorage_iscsi=disabled \
		-Dstorage_iscsi_direct=disabled -Dstorage_rbd=disabled \
		-Dstorage_vstorage=disabled \
		-Dnls=disabled -Dnss=disabled \
		-Dinit_script=openrc \
		-Dudev=enabled -Dcurl=enabled -Dreadline=enabled -Dlibnl=enabled \
		-Dattr=enabled -Dblkid=disabled
	ninja -C build
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C build install
	# Runtime firewall backend: nftables (Saphira carries nftables; no
	# iptables). libvirt falls back to iptables backend when unset.
	install -d "$PKGDEST/etc/libvirt"
	[ -f "$PKGDEST/etc/libvirt/network.conf" ] && \
		sed -i 's|^#*\s*firewall_backend\s*=.*|firewall_backend = "nftables"|' \
			"$PKGDEST/etc/libvirt/network.conf"
	[ -f "$PKGDEST/etc/libvirt/network.conf" ] || \
		printf '# Saphira: nftables firewall backend (no iptables)\nfirewall_backend = "nftables"\n' \
			> "$PKGDEST/etc/libvirt/network.conf"	# Dual-init policy: both definitions ship unconditionally; neither is
	# enabled or started at install.
	install -D -m 0755 "$RECIPE_DIR/files/virtqemud.initd" \
		"$PKGDEST/etc/init.d/virtqemud"
	install -D -m 0644 "$RECIPE_DIR/files/virtqemud.service" \
		"$PKGDEST/usr/lib/systemd/system/virtqemud.service"
	install -D -m 0755 "$RECIPE_DIR/files/virtstoraged.initd" \
		"$PKGDEST/etc/init.d/virtstoraged"
	install -D -m 0644 "$RECIPE_DIR/files/virtstoraged.service" \
		"$PKGDEST/usr/lib/systemd/system/virtstoraged.service"
	install -D -m 0755 "$RECIPE_DIR/files/virtnetworkd.initd" \
		"$PKGDEST/etc/init.d/virtnetworkd"
	install -D -m 0644 "$RECIPE_DIR/files/virtnetworkd.service" \
		"$PKGDEST/usr/lib/systemd/system/virtnetworkd.service"
	install -D -m 0755 "$RECIPE_DIR/files/virtnodedevd.initd" \
		"$PKGDEST/etc/init.d/virtnodedevd"
	install -D -m 0644 "$RECIPE_DIR/files/virtnodedevd.service" \
		"$PKGDEST/usr/lib/systemd/system/virtnodedevd.service"
	install -D -m 0755 "$RECIPE_DIR/files/virtsecretd.initd" \
		"$PKGDEST/etc/init.d/virtsecretd"
	install -D -m 0644 "$RECIPE_DIR/files/virtsecretd.service" \
		"$PKGDEST/usr/lib/systemd/system/virtsecretd.service"
	install -D -m 0755 "$RECIPE_DIR/files/virtproxyd.initd" \
		"$PKGDEST/etc/init.d/virtproxyd"
	install -D -m 0644 "$RECIPE_DIR/files/virtproxyd.service" \
		"$PKGDEST/usr/lib/systemd/system/virtproxyd.service"
	install -D -m 0755 "$RECIPE_DIR/files/virtlogd.initd" \
		"$PKGDEST/etc/init.d/virtlogd"
	install -D -m 0644 "$RECIPE_DIR/files/virtlogd.service" \
		"$PKGDEST/usr/lib/systemd/system/virtlogd.service"
	install -D -m 0755 "$RECIPE_DIR/files/virtlockd.initd" \
		"$PKGDEST/etc/init.d/virtlockd"
	install -D -m 0644 "$RECIPE_DIR/files/virtlockd.service" \
		"$PKGDEST/usr/lib/systemd/system/virtlockd.service"
	# The two state-holding daemons must never be restart-looped: a
	# restart mid-operation can leave a lock or a log inconsistent.
	for d in virtlogd virtlockd; do
		grep -q 'Restart=' "$RECIPE_DIR/files/$d.service" && {
			echo "ERROR: libvirt $d.service must not set Restart=" >&2
			return 1
		}
	done
	[ -e "$PKGDEST/etc/init.d/virtqemud" ] || { echo "ERROR: libvirt payload is missing etc/init.d/virtqemud" >&2; return 1; }
	[ -e "$PKGDEST/usr/lib/systemd/system/virtqemud.service" ] || { echo "ERROR: libvirt payload is missing usr/lib/systemd/system/virtqemud.service" >&2; return 1; }
	[ -e "$PKGDEST/etc/init.d/virtstoraged" ] || { echo "ERROR: libvirt payload is missing etc/init.d/virtstoraged" >&2; return 1; }
	[ -e "$PKGDEST/usr/lib/systemd/system/virtstoraged.service" ] || { echo "ERROR: libvirt payload is missing usr/lib/systemd/system/virtstoraged.service" >&2; return 1; }
	[ -e "$PKGDEST/etc/init.d/virtnetworkd" ] || { echo "ERROR: libvirt payload is missing etc/init.d/virtnetworkd" >&2; return 1; }
	[ -e "$PKGDEST/usr/lib/systemd/system/virtnetworkd.service" ] || { echo "ERROR: libvirt payload is missing usr/lib/systemd/system/virtnetworkd.service" >&2; return 1; }
	[ -e "$PKGDEST/etc/init.d/virtnodedevd" ] || { echo "ERROR: libvirt payload is missing etc/init.d/virtnodedevd" >&2; return 1; }
	[ -e "$PKGDEST/usr/lib/systemd/system/virtnodedevd.service" ] || { echo "ERROR: libvirt payload is missing usr/lib/systemd/system/virtnodedevd.service" >&2; return 1; }
	[ -e "$PKGDEST/etc/init.d/virtsecretd" ] || { echo "ERROR: libvirt payload is missing etc/init.d/virtsecretd" >&2; return 1; }
	[ -e "$PKGDEST/usr/lib/systemd/system/virtsecretd.service" ] || { echo "ERROR: libvirt payload is missing usr/lib/systemd/system/virtsecretd.service" >&2; return 1; }
	[ -e "$PKGDEST/etc/init.d/virtproxyd" ] || { echo "ERROR: libvirt payload is missing etc/init.d/virtproxyd" >&2; return 1; }
	[ -e "$PKGDEST/usr/lib/systemd/system/virtproxyd.service" ] || { echo "ERROR: libvirt payload is missing usr/lib/systemd/system/virtproxyd.service" >&2; return 1; }
	[ -e "$PKGDEST/etc/init.d/virtlogd" ] || { echo "ERROR: libvirt payload is missing etc/init.d/virtlogd" >&2; return 1; }
	[ -e "$PKGDEST/usr/lib/systemd/system/virtlogd.service" ] || { echo "ERROR: libvirt payload is missing usr/lib/systemd/system/virtlogd.service" >&2; return 1; }
	[ -e "$PKGDEST/etc/init.d/virtlockd" ] || { echo "ERROR: libvirt payload is missing etc/init.d/virtlockd" >&2; return 1; }
	[ -e "$PKGDEST/usr/lib/systemd/system/virtlockd.service" ] || { echo "ERROR: libvirt payload is missing usr/lib/systemd/system/virtlockd.service" >&2; return 1; }

}
