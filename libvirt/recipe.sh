pkgname=libvirt
pkgver=12.6.0
pkgrel=21
# r21: main depends on qemu-virgl (2026-10-23): the qemu GL split
# (virgl/egl-headless/SPICE-display modules) stays inside the libvirt
# offering - a libvirt install without it loses SPICE display (the
# module_dep chain needs ui-opengl), so the edge is hard, like lxc.
# Depends-metadata change only; payload identical to r20.
# r20: main depends on the libvirt-lxc split (LXC is core to this
# programme, not optional): ordinary upgrades can then never silently
# lose virtlxcd the way r13->r18 did. Umbrella tolerance reverted:
# missing members fail LOUDLY again (the depends edge makes absence
# abnormal, and abnormal must be loud, never skipped).
# r19: umbrella tolerates absent optionals (skip with notice; present
# members failing still fail the stack) so a libvirt upgrade without
# the lxc split installed degrades loudly instead of breaking start.
# systemd already degrades via Wants (non-fatal); this aligns OpenRC.
# r18: declare subpackages="libvirt-lxc" so the split list takes
# effect (r17 staged monolithic: lists without declaration are
# ignored, proven). Payload move only; supersedes unstaged r17.
# r17: explicit libvirtd.conf (socket group libvirt:174 + 0770/0770/
# 0700 — the access policy with polkit disabled) and the libvirt
# socket group in the identity fragment. Hand-made libvirt:981 on
# early hosts must be deleted before installing (sockets recreate).
# r16: Environment=PATH (with /sbin:/bin) in all daemon units: this
# systemd build omits them from the default PATH and daemons spawn
# bare-name helpers (tc, ip), proven by virsh net-start failing on
# hatchling. Supersedes unstaged r15 (never published).
# r15: qemu home /var/empty (no-home idiom; a real home path fails
# clean-root install tests at the reconciler chown). r14's staged
# transaction is superseded.
# r14: libcap-ng runtime dep (r13 shipped it linked but undeclared;
# Hatchling proved it with a manual install), virtlxcd integrated
# into the libvirtd umbrella both init systems (member lists +
# PartOf, landing together as the units required), qemu:qemu 173
# identity wired (6-field form, valid on old and new helpers; account
# provisioned ahead of the coordinated -Dqemu_user flip, kvm
# membership deferred with the unpublished grammar). Split list
# materializes under the r80 builder.
# r13: Batch-1 enablement (every probe-satisfiable feature on):
# driver_libvirtd + driver_remote + driver_lxc (LXC needs the driver
# infra, NOT the monolith: meson_options 67-68,85 + meson.build:1596;
# -Dlibvirtd stays disabled and the no-monolith assert below holds),
# driver_ch (curl only, meson.build:1628), driver_vmware (no deps,
# meson.build:1784), driver_interface (pciaccess+udev+infra),
# driver_openvz (json_c+infra), driver_test (no deps), driver_esx
# (curl only; openwsman belongs to Hyper-V, not ESX), libssh+libssh2,
# fuse, nls, blkid, libpcap, capng, numactl (numa.pc ships in the main
# numactl package, no -dev split: proven in repository.db), libiscsi,
# storage_dir/fs (were implicit auto-on; now explicit), storage_lvm
# (linux-only probe; lvm2 tools published), storage_disk (parted-dev),
# storage_scsi (linux-only), storage_iscsi + iscsi_direct (probes
# satisfiable; iscsiadm at runtime is an open-iscsi follow-up, same
# precedent as selinux without a policy package), storage_zfs (no probe
# dep; saphira-zfs-userspace published). driver_bhyve stays DISABLED:
# FreeBSD-only driver, must never be forced on Linux. firewalld(+_zone)
# stays disabled PENDING firewalld publication (queued; flips to
# enabled with no other change once published): never auto-enabled,
# never started, nftables coexistence tested before runtime use, no
# systemd-only requirements. virtlxcd units ship dual-init, never
# enabled; libvirt-lxc named split carries the 5 certain paths
# (forward-compatible: inert under the pre-splits builder).
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Libvirt control plane: modular daemons (virtqemud/virtlxcd/storaged/networkd/nodedevd/secretd/interfaced/nwfilterd/logd/lockd, virtproxyd TLS entry) under the libvirtd umbrella service, virsh, QEMU/LXC/network/storage drivers (headless, no GUI)'
license='LGPL-2.1-or-later'
origin=libvirt
repo=saphira
url=https://libvirt.org/
# Vendored: https://download.libvirt.org/libvirt-12.6.0.tar.xz
libvirt_sha256=1592256deb76fc94028ff083a4d9f06a74f3b92a66a1794f37bc26f21430c888
# Named split declaration (builder splits mechanism): files/ carries
# split-libvirt-lxc.list, but the builder only partitions subpackages
# named here (r17 proved lists alone are inert: single APK staged).
# libvirt-lxc holds daemon+binary+driver+conf+units for LXC.
subpackages="libvirt-lxc"

# libpciaccess is a RUNTIME dep: libvirt_driver_nodedev.so needs
# libpciaccess.so.0 (r2 shipped it only as a makedepend and failed at
# daemon start on clean installs).
# Runtime DT_NEEDED/tool closure for the newly enabled drivers (same
# rule as the libpciaccess precedent above): remote links libssh[2],
# numactl/capng link on enable, storage-fuse links fuse3, iscsi-direct
# links libiscsi, disk links libparted, nwfilter uses libpcap, nls
# needs gettext, lvm/disk/zfs pools shell their tools (lvm2, parted,
# saphira-zfs-userspace — all published; iscsiadm is not, see r13 note).
# libvirt-lxc: the LXC driver split is a hard dependency, not an
# option (see r20 note): upgrades must carry it automatically.
# qemu-virgl (2026-10-23): the GL split stays inside the libvirt
# offering - a libvirt host is a GPU-capable virtualisation host, so
# virgl/egl-headless travel with it while plain qemu stays lean. No
# payload change (depends only). Sequencing note: qemu-virgl must be
# published before libvirt's next rebuild, or resolve refuses (same
# rule as the firmware meta) - qemu r10 is already queued ahead.
depends="glib libnl libxml2 readline zlib curl openssl libtirpc gnutls json-c libbsd libxcrypt acl attr udev dnsmasq qemu qemu-virgl dmidecode nettle libtasn1 libunistring libpciaccess iproute2 nftables libapparmor libselinux libssh libssh2 numactl fuse3 libiscsi parted libpcap gettext lvm2 saphira-zfs-userspace libcap-ng libvirt-lxc"
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
	libapparmor-dev
	libselinux-dev
	libsepol-dev
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
	gettext-dev
	fuse3-dev
	libiscsi-dev
	libssh-dev
	libssh2-dev
	libcap-ng-dev
	numactl
	parted-dev
	libpcap-dev
	util-linux-dev
"
# numactl is deliberately the bare main package, not a -dev split:
# numa.h + numa.pc ship in main (proven in repository.db); no
# numactl-dev exists. Do not "fix" this into a missing package.
# util-linux-dev carries blkid.pc for -Dblkid=enabled (r13 proved the
# probe fails closed without it).
# numactl is deliberately the bare main package, not a -dev split:
# numa.h + numa.pc ship in main (proven in repository.db); no
# numactl-dev exists. Do not "fix" this into a missing package.

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
# libselinux-dev + libsepol-dev ride along one level deeper still:
# libselinux links libsepol shared (its DT_NEEDED closure, documented
# in that recipe's own RUNTIME analysis), so the probe's link test
# sees the full closure in the sysroot. If that edge ever proves
# unnecessary it is inert - makedepends never ship - and the explicit
# -Dselinux=enabled probe fails the build either way rather than
# silently dropping the driver.
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
# No polkit/dbus, no GUI. -Dpolkit=disabled is COORDINATION-gated
# (nova authenticates against root-only sockets today; flipping needs
# the nova-side rules first — OpenStack lane; enablement of unrelated
# drivers does not wait on it). -Daudit=disabled is BLOCKED_BY_audit
# (recipe exists, unpublished). libpcap now enabled (libpcap-dev
# published) for nwfilter.
# selinux ENABLED (libselinux 3.11 + libsepol 3.11 published: lib and
# .pc verified): -Dselinux=enabled forces the probe to fail the build
# if the headers ever vanish instead of silently dropping the driver;
# the security driver itself probes at daemon start (is_selinux_enabled)
# and stays inert where the kernel offers no SELinux, so this changes
# nothing on machines without it. Saphira kernels already carry
# CONFIG_SECURITY_SELINUX=y built-in (default security SELINUX), so no
# kernel change is needed for the SELinux driver to load - but loading
# is not enforcing: functional enforcement is NOT claimed without a
# policy package and a real runtime test, both filed follow-ups.
# apparmor ENABLED (libapparmor 4.x published: lib + .pc verified):
# -Dapparmor=enabled forces the probe to fail the build if the headers
# ever vanish instead of silently dropping the driver; the security
# driver itself is auto-selected only when the kernel offers AppArmor
# (AppArmorSecurityManagerProbe reads
# /sys/kernel/security/apparmor/profiles and self-disables otherwise -
# proven in the 12.6.0 source, so this is inert on AppArmor-less
# kernels and changes nothing for existing VMs). Profiles install by
# default. Functional enforcement is NOT claimed: it needs (a) a kernel
# with CONFIG_SECURITY_APPARMOR (7.1.5-akadata has it NOT SET; default
# security there is SELINUX), (b) an apparmor_parser package (LXC
# libapparmor is library-only by design), (c) real runtime tests.
# All three are filed follow-ups; no Egg or default-config change here.
# -Dcapng=enabled (libcap-ng published) and -Dnumactl=enabled (numa.pc
# in main) now: the qemu-identity privilege question moved to the
# coordinated qemu_user migration, and numactl is placement correctness,
# not tuning decoration. -Dqemu_user=root -Dqemu_group=root stay:
# COORDINATION-gated (guest image DAC + nova User= wiring — OpenStack
# lane; unrelated driver enablement does not wait on it).
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
		-Ddriver_libvirtd=enabled -Ddriver_remote=enabled \
		-Ddriver_qemu=enabled -Ddriver_network=enabled \
		-Ddriver_secrets=enabled \
		-Ddriver_lxc=enabled -Ddriver_ch=enabled \
		-Ddriver_interface=enabled -Ddriver_openvz=enabled \
		-Ddriver_test=enabled \
		-Ddriver_bhyve=disabled -Ddriver_vmware=enabled \
		-Ddriver_esx=enabled \
		-Ddriver_libxl=disabled -Ddriver_hyperv=disabled \
		-Ddriver_vz=disabled -Ddriver_vbox=disabled \
		-Dqemu_user=root -Dqemu_group=root \
		-Dpolkit=disabled -Dselinux=enabled -Dapparmor=enabled \
		-Dsecdriver_selinux=enabled -Dsecdriver_apparmor=enabled \
		-Daudit=disabled -Dnumactl=enabled -Dcapng=enabled \
		-Dsanlock=disabled -Dsasl=disabled -Dglusterfs=disabled \
		-Dlibiscsi=enabled -Dfuse=enabled \
		-Dlibssh=enabled -Dlibssh2=enabled \
		-Dnetcf=disabled -Dopenwsman=disabled \
		-Dfirewalld=disabled -Dfirewalld_zone=disabled \
		-Dstorage_dir=enabled -Dstorage_fs=enabled \
		-Dstorage_lvm=enabled -Dstorage_disk=enabled \
		-Dstorage_scsi=enabled -Dstorage_iscsi=enabled \
		-Dstorage_iscsi_direct=enabled -Dstorage_zfs=enabled \
		-Dstorage_gluster=disabled -Dstorage_rbd=disabled \
		-Dstorage_mpath=disabled -Dstorage_vstorage=disabled \
		-Dnls=enabled -Dnss=disabled \
		-Dinit_script=openrc \
		-Dudev=enabled -Dcurl=enabled -Dreadline=enabled -Dlibnl=enabled \
		-Dattr=enabled -Dblkid=enabled -Dlibpcap=enabled
	# Disabled-with-reason ledger (explicit blockers, never silent):
	# driver_bhyve: FreeBSD-only driver, must never be forced on Linux.
	# driver_libxl: BLOCKED_BY_xen-libs (recipe exists, unpublished).
	# driver_esx: curl only (openwsman belongs to Hyper-V, not ESX).
	# driver_hyperv: BLOCKED_BY_openwsman (recipe exists, unpublished).
	# driver_vz + driver_vbox: no Parallels/VirtualBox SDK in tree.
	# netcf: dead upstream, no obtainable source. storage_gluster:
	# BLOCKED_BY_glusterfs (recipe exists, unpublished). storage_rbd:
	# no Ceph scale. storage_mpath: no devmapper provider (maintainer
	# multipath call pending). storage_vstorage: no SDK. sasl:
	# BLOCKED_BY_cyrus-sasl. sanlock: BLOCKED_BY_sanlock. openwsman:
	# BLOCKED_BY_openwsman. firewalld(+_zone): PENDING firewalld
	# publication (queued; flips to enabled with no other change once
	# published — never auto-enabled/started, nftables coexistence
	# tested before runtime use, no systemd-only requirements).
	# audit: BLOCKED_BY_audit. nss: nss.h provider on musl UNCONFIRMED
	# (no usr/include/nss.h row in repository.db) — flip to enabled when
	# a build proves the header; the probe fails closed either way.
	# polkit + qemu_user/group: COORDINATION-gated, OpenStack lane.
	# docs/tests: Saphira policy (man-disabled precedent; tests run separately).
	ninja -C build
	# API XML for language bindings (python-libvirt resolves it via
	# pkg-config libvirt_api): generated with the stdlib-only
	# apibuild.py, since -Ddocs=disabled skips the docs tree that
	# would otherwise install it. Fails closed when any of the four
	# files is missing.
	mkdir -p "$BUILDDIR/apixml"
	python3 "$SRC/scripts/apibuild.py" "$SRC/docs" "$BUILDDIR/apixml" || {
		echo "ERROR: apibuild failed" >&2
		return 1
	}
	for api in libvirt libvirt-qemu libvirt-lxc libvirt-admin; do
		[ -f "$BUILDDIR/apixml/$api-api.xml" ] || {
			echo "ERROR: apibuild did not produce $api-api.xml" >&2
			return 1
		}
	done
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C build install
	# API XML the .pc file advertises (pkg-config libvirt_api):
	# generated above, installed where bindings expect it.
	install -d "$PKGDEST/usr/share/libvirt/api"
	install -m 0644 "$BUILDDIR"/apixml/*-api.xml \
		"$PKGDEST/usr/share/libvirt/api/"
	# Runtime firewall backend: nftables (Saphira carries nftables; no
	# iptables). libvirt falls back to iptables backend when unset.
	install -d "$PKGDEST/etc/libvirt"
	[ -f "$PKGDEST/etc/libvirt/network.conf" ] && \
		sed -i 's|^#*\s*firewall_backend\s*=.*|firewall_backend = "nftables"|' \
			"$PKGDEST/etc/libvirt/network.conf"
	[ -f "$PKGDEST/etc/libvirt/network.conf" ] || \
		printf '# Saphira: nftables firewall backend (no iptables)\nfirewall_backend = "nftables"\n' \
			> "$PKGDEST/etc/libvirt/network.conf"
	# Daemon access policy (no polkit): socket group + modes are the
	# only client gate, owned content (see files/libvirtd.conf).
	# Upstream installs no libvirtd.conf, so this path is always new
	# on first install; operator modifications park as .apk-new.
	install -m 0644 "$RECIPE_DIR/files/libvirtd.conf" \
		"$PKGDEST/etc/libvirt/libvirtd.conf"
	# Runtime identity declaration: qemu:qemu 173:173 (provisioned
	# ahead of use; -Dqemu_user stays root until the coordinated
	# privilege migration). 6-field form parses on old and new
	# helpers alike; kvm membership waits for the published grammar.
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/libvirt" \
		"$PKGDEST/usr/share/saphira/accounts.d/libvirt"
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/libvirt.legacy" \
		"$PKGDEST/usr/share/saphira/accounts.d/libvirt.legacy"	# Dual-init policy: both definitions ship unconditionally; neither is
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
	# LXC driver units, dual-init, never enabled at install (policy).
	install -D -m 0755 "$RECIPE_DIR/files/virtlxcd.initd" \
		"$PKGDEST/etc/init.d/virtlxcd"
	install -D -m 0644 "$RECIPE_DIR/files/virtlxcd.service" \
		"$PKGDEST/usr/lib/systemd/system/virtlxcd.service"
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
	[ -e "$PKGDEST/etc/init.d/virtlxcd" ] || { echo "ERROR: libvirt payload is missing etc/init.d/virtlxcd" >&2; return 1; }
	[ -e "$PKGDEST/usr/lib/systemd/system/virtlxcd.service" ] || { echo "ERROR: libvirt payload is missing usr/lib/systemd/system/virtlxcd.service" >&2; return 1; }
	[ -e "$PKGDEST/usr/sbin/virtlxcd" ] || { echo "ERROR: libvirt payload is missing usr/sbin/virtlxcd (driver_lxc)" >&2; return 1; }
	[ -e "$PKGDEST/usr/lib/libvirt/connection-driver/libvirt_driver_lxc.so" ] || { echo "ERROR: libvirt payload is missing connection-driver/libvirt_driver_lxc.so" >&2; return 1; }
	[ -e "$PKGDEST/etc/libvirt/lxc.conf" ] || { echo "ERROR: libvirt payload is missing etc/libvirt/lxc.conf" >&2; return 1; }
	[ -e "$PKGDEST/etc/libvirt/libvirtd.conf" ] || { echo "ERROR: libvirt payload is missing etc/libvirt/libvirtd.conf" >&2; return 1; }
	[ -e "$PKGDEST/etc/init.d/libvirtd" ] || { echo "ERROR: libvirt payload is missing etc/init.d/libvirtd (umbrella)" >&2; return 1; }
	[ -e "$PKGDEST/usr/lib/systemd/system/libvirtd.service" ] || { echo "ERROR: libvirt payload is missing usr/lib/systemd/system/libvirtd.service (umbrella)" >&2; return 1; }
	# The umbrella must orchestrate, never resurrect the monolith: no
	# libvirtd binary may be installed by this package.
	[ ! -e "$PKGDEST/usr/sbin/libvirtd" ] || { echo "ERROR: libvirt payload must not contain a monolithic usr/sbin/libvirtd" >&2; return 1; }

}
