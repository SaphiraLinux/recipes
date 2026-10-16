pkgname=libvirt
pkgver=12.6.0
pkgrel=9
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Libvirt control plane: modular daemons (virtqemud/storaged/networkd/nodedevd/secretd/interfaced/nwfilterd/logd/lockd, virtproxyd TLS entry) under the libvirtd umbrella service, virsh, QEMU/network/storage drivers (headless, no GUI)'
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
	attr-dev
	binutils
	curl-dev
	gawk
	gcc
	gnutls-dev
	nettle-dev
	glib-dev
	libffi-dev
	libnl-dev
	libtirpc-dev
	libtasn1-dev
	libxml2-dev
	json-c-dev
	libpciaccess
	libxcrypt-dev
	make
	meson
	ninja
	pcre2-dev
	pkgconf
	python3
	libxslt
	perl
	readline-dev
	udev-dev
	zlib-dev
"

# attr-dev is a DIRECT build input (-Dattr=enabled probes libattr.pc;
# r6 omitted it and meson fails at "Dependency libattr not found" - the
# runtime attr dep alone does not put the .pc in the sysroot).
# pcre2-dev/libffi-dev are not direct inputs either: glib-2.0.pc
# Requires libpcre2-8 (and gobject-2.0.pc Requires libffi), so the
# meson pkg-config probes fail without them in the sysroot. Same edge
# as avahi documents for its own glib consumption. gnutls-dev,
# libtirpc-dev and json-c-dev likewise track their recipes' -dev
# splits: the .pc files no longer ship in the main packages, so the
# runtime names alone leave meson with "Dependency not found".
# libtasn1-dev is one level deeper still (gnutls.pc Requires libtasn1).
# (libpciaccess and libxslt stay as-is: no -dev split / xsltproc
# binary in main.)
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
# -Drunstatedir=/var/run is load-bearing Saphira policy, not cosmetic:
# libvirt's remote/SSH compatibility path (remoteGetUNIXSocketHelper)
# deliberately builds the socket under $LOCALSTATEDIR, i.e. in
# /var/run/libvirt, explicitly assuming a /var/run -> /run alias that
# Saphira forbids (/var/run and /run are separate real directories).
# Without this flag RUNSTATEDIR defaults to the /run tree, so the
# daemons listen there while virt-ssh-helper asks in /var/run/libvirt
# and every qemu+ssh connection fails with ENOENT.
# Setting runstatedir to /var/run makes the daemons agree with the path
# the SSH helper already expects. Ordinary-daemon sockets therefore live
# under /var/run/libvirt; nothing in this package references /run/libvirt.
# No polkit/dbus/audit/selinux, no GUI, nwfilter+libpcap deferred.
recipe_build()
{
	LVBALL="$RECIPE_DIR/files/libvirt-12.6.0.tar.xz"
	echo "$libvirt_sha256  $LVBALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$LVBALL"
	patch -Np1 -i "$RECIPE_DIR/files/0001-secret-init-use-bin-sh-non-usrmerged.patch"
	meson setup build "$SRC" --prefix=/usr \
		-Drunstatedir=/var/run \
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
	install -D -m 0755 "$RECIPE_DIR/files/virtinterfaced.initd" \
		"$PKGDEST/etc/init.d/virtinterfaced"
	install -D -m 0644 "$RECIPE_DIR/files/virtinterfaced.service" \
		"$PKGDEST/usr/lib/systemd/system/virtinterfaced.service"
	install -D -m 0755 "$RECIPE_DIR/files/virtnwfilterd.initd" \
		"$PKGDEST/etc/init.d/virtnwfilterd"
	install -D -m 0644 "$RECIPE_DIR/files/virtnwfilterd.service" \
		"$PKGDEST/usr/lib/systemd/system/virtnwfilterd.service"
	# The libvirtd umbrella: orchestration over the modular daemons, not
	# a daemon itself. Restores the stable operator contract (enable /
	# start / restart / stop / status libvirtd) without resurrecting the
	# monolith. Never enabled or started at install: the operator
	# explicitly chooses systemctl enable --now libvirtd.
	install -D -m 0755 "$RECIPE_DIR/files/libvirtd.initd" \
		"$PKGDEST/etc/init.d/libvirtd"
	install -D -m 0644 "$RECIPE_DIR/files/libvirtd.service" \
		"$PKGDEST/usr/lib/systemd/system/libvirtd.service"
	# The two state-holding daemons must never be restart-looped: a
	# restart mid-operation can leave a lock or a log inconsistent.
	# Anchor at line start: the units document this with a "# NEVER
	# Restart=" comment, which an unanchored grep would match.
	for d in virtlogd virtlockd; do
		grep -q '^Restart=' "$RECIPE_DIR/files/$d.service" && {
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
	[ -e "$PKGDEST/etc/init.d/virtinterfaced" ] || { echo "ERROR: libvirt payload is missing etc/init.d/virtinterfaced" >&2; return 1; }
	[ -e "$PKGDEST/usr/lib/systemd/system/virtinterfaced.service" ] || { echo "ERROR: libvirt payload is missing usr/lib/systemd/system/virtinterfaced.service" >&2; return 1; }
	[ -e "$PKGDEST/etc/init.d/virtnwfilterd" ] || { echo "ERROR: libvirt payload is missing etc/init.d/virtnwfilterd" >&2; return 1; }
	[ -e "$PKGDEST/usr/lib/systemd/system/virtnwfilterd.service" ] || { echo "ERROR: libvirt payload is missing usr/lib/systemd/system/virtnwfilterd.service" >&2; return 1; }
	[ -e "$PKGDEST/etc/init.d/libvirtd" ] || { echo "ERROR: libvirt payload is missing etc/init.d/libvirtd (umbrella)" >&2; return 1; }
	[ -e "$PKGDEST/usr/lib/systemd/system/libvirtd.service" ] || { echo "ERROR: libvirt payload is missing usr/lib/systemd/system/libvirtd.service (umbrella)" >&2; return 1; }
	# The umbrella must orchestrate, never resurrect the monolith: no
	# libvirtd binary may be installed by this package.
	[ ! -e "$PKGDEST/usr/sbin/libvirtd" ] || { echo "ERROR: libvirt payload must not contain a monolithic usr/sbin/libvirtd" >&2; return 1; }

}
