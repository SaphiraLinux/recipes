pkgname=libvirt
pkgver=12.6.0
pkgrel=5
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Libvirt control plane: libvirtd, virsh, QEMU/network/storage drivers (headless, no GUI)'
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

# KISS server build: monolithic libvirtd, QEMU/network/storage drivers,
# no polkit/dbus/audit/selinux, no GUI, nwfilter+libpcap deferred.
recipe_build()
{
	LVBALL="$RECIPE_DIR/files/libvirt-12.6.0.tar.xz"
	echo "$libvirt_sha256  $LVBALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$LVBALL"
	patch -Np1 -i "$RECIPE_DIR/files/0001-secret-init-use-bin-sh-non-usrmerged.patch"
	meson setup build "$SRC" --prefix=/usr \
		-Dpackager=Saphira \
		-Ddocs=disabled -Dtests=disabled \
		-Dlibvirtd=enabled -Dremote_default_mode=legacy \
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
		-Dinit_script=systemd \
		-Dudev=enabled -Dcurl=enabled -Dreadline=enabled -Dlibnl=enabled \
		-Dattr=enabled -Dblkid=disabled
	ninja -C build
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C build install
	install -d "$PKGDEST/etc/init.d"
	install -m 755 "$RECIPE_DIR/files/libvirtd.initd" "$PKGDEST/etc/init.d/libvirtd"
	# Runtime firewall backend: nftables (Saphira carries nftables; no
	# iptables). libvirt falls back to iptables backend when unset.
	install -d "$PKGDEST/etc/libvirt"
	[ -f "$PKGDEST/etc/libvirt/network.conf" ] && \
		sed -i 's|^#*\s*firewall_backend\s*=.*|firewall_backend = "nftables"|' \
			"$PKGDEST/etc/libvirt/network.conf"
	[ -f "$PKGDEST/etc/libvirt/network.conf" ] || \
		printf '# Saphira: nftables firewall backend (no iptables)\nfirewall_backend = "nftables"\n' \
			> "$PKGDEST/etc/libvirt/network.conf"
	# Saphira is non-usrmerged: tc lives in /sbin. systemd's default
	# service PATH omits /sbin, so give the daemon the full Saphira PATH
	# (tracked for a proper systemd split-bin fix separately).
	install -d "$PKGDEST/usr/lib/systemd/system/libvirtd.service.d"
	printf '[Service]\nEnvironment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\n' \
		> "$PKGDEST/usr/lib/systemd/system/libvirtd.service.d/10-saphira-path.conf"
}
