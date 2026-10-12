#!/bin/sh
# Slurm workload manager core: client tools, shared libraries, plugins,
# and the slurmctld/slurmd/slurmstepd/sackd daemons with their dual-init
# definitions. One product, one APK.
#
# Accounting (slurmdbd + the mysql plugin) lives in the source-sharing
# /recipes/slurm-accounting recipe so no compute node inherits MariaDB
# libraries. Daemons are enabled/disabled individually at runtime;
# package boundaries do not mirror daemon boundaries.
#
# Site-neutral: no hostnames, addresses, topology or cluster policy
# anywhere in this recipe. Shipped configuration is upstream examples
# only; live slurm.conf/gres.conf/cgroup.conf are generated on the
# target by saphira-cluster and never committed or shipped.

pkgname=slurm
pkgver=26.05.4
pkgrel=1
# r1: initial Slurm packaging. UNBUILT: no builder run yet; every flag
# below is proven against the vendored 26.05.4 ./configure --help,
# slurm.spec and auxdir/x_ac_databases.m4, not against a build log.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Slurm workload manager (client tools, libraries and plugins)"
license="GPL-2.0-or-later"
origin=slurm
repo=saphira
url=https://slurm.schedmd.com/
vendor=https://github.com/SchedMD/slurm/releases/download/slurm-26-05-4-1/slurm-26.05.4.tar.bz2
sha256=035f4b193d4de979ba5381beca206a50b6b886b2793b06f68a1ce7e67022b06a

depends="
    dbus
    hwloc
    json-c
    linux-pam
    lz4
    readline
    saphira-base-accounts
"

makedepends="
    binutils
    dbus-dev
    gawk
    gcc
    hwloc
    json-c-dev
    linux-pam
    lz4-dev
    make
    perl
    pkgconf
    readline-dev
    systemd-dev
"

subpackages="slurm-dev slurm-doc"

# Shared configure matrix for the Slurm recipes in this repo. Any flag
# change here must be mirrored in /recipes/slurm-accounting (plus its
# documented mysql delta) so every output shares one plugin ABI.
# --sysconfdir=/etc/slurm: upstream RPM layout; compiled-in default
#   config path, so saphira-cluster writes exactly one well-known path.
# --runstatedir=/var/run: Saphira volatile runtime root (real dir,
#   never an alias of /run).
# --without-rpath, --disable-x11/--disable-gtktest/--disable-sview:
#   headless, no desktop stack.
# --enable-cgroupv2: load-bearing for resource isolation; explicit so a
#   missing header fails closed instead of silently disabling it.
# --disable-slurmrestd: needs libjwt + an HTTP parser library, neither
#   packaged yet; restd is a documented follow-up, not silent breakage.
# --without-munge: MUNGE is not packaged yet; auth/slurm is built in
#   and both mechanisms are proven before a default is declared.
# --without-pmix: external PMIx is not packaged yet; built-in
#   mpi/pmi2 plumbing is unaffected. PMIx runtime is a follow-up.
# --enable-pam --with-pam_dir=/usr/lib/security: Saphira platform
#   policy builds with PAM (openssh precedent). linux-pam ships
#   modules in /usr/lib/security with headers in main (no -dev
#   split, like hwloc), proven by installing the published APK.
#   Without this, configure warns and silently drops PAM support.
# systemd-dev is a library/development dependency only: dbus-1.pc
#   Requires.private libsystemd and libdbus-1.so DT_NEEDEDs
#   libsystemd.so.0 (both proven), so configure's dbus check fails
#   without libsystemd.pc. This is NOT an init-system dependency:
#   no systemd package, no units, no guards; OpenRC stays fully
#   supported. Runtime intentionally unchanged: dbus already brings
#   systemd-libs transitively; a direct systemd-libs dep is added
#   only if Slurm binaries prove a direct DT_NEEDED on libsystemd.
# --with-hwloc/--with-json/--with-lz4/--with-readline: packaged deps,
#   topology detection, CLI completion, JSON output. hwloc and
#   linux-pam ship headers in main (no -dev split); the -dev names
#   below are only where the tree provides them.
# --without-mysql_config: NO MySQL support in core, deterministically.
#   Without this flag configure auto-searches for mysql_config AND
#   mariadb_config, so a builder carrying MariaDB dev files would
#   silently enable it (verified in auxdir/x_ac_databases.m4). With the
#   flag, support is disabled with a notice and never searched.
#   Accounting lives in /recipes/slurm-accounting, which requests MySQL
#   explicitly and fails closed without it.
# --without-systemdsystemunitdir: upstream units are never installed;
#   this recipe ships its own dual-init definitions below.
slurm_configure()
{
	./configure \
		--prefix=/usr \
		--sysconfdir=/etc/slurm \
		--localstatedir=/var \
		--runstatedir=/var/run \
		--libdir=/usr/lib \
		--without-rpath \
		--without-systemdsystemunitdir \
		--enable-pkgconfig \
		--enable-cgroupv2 \
		--disable-x11 \
		--disable-gtktest \
		--disable-sview \
		--disable-slurmrestd \
		--without-munge \
		--without-pmix \
		--enable-pam \
		--with-pam_dir=/usr/lib/security \
		--with-hwloc \
		--with-json \
		--with-lz4 \
		--with-readline \
		--without-mysql_config
}

recipe_build()
{
	cd "$SRC"
	# musl exposes cpu_set_t and the sched affinity API only under
	# _GNU_SOURCE (proven: src/common/xsched.h cpu_set_t); attr and
	# traceroute precedent sets it via CFLAGS for the whole tree.
	export CFLAGS="-D_GNU_SOURCE ${CFLAGS-}"
	slurm_configure
	make
}
# Musl port patches (files/patches/, applied by the worker):
# - 0001-callerid-musl-inet-nsap-addr: musl omits the legacy BSD
#   inet_nsap_addr() used only to parse plain-hex /proc/net/tcp{,6}
#   fields; file-static equivalent, identical on that input domain.
# - 0002-resolv-musl-res-n-apis: musl provides struct __res_state
#   and classic res_search() but not res_ninit/res_nsearch/res_nclose;
#   thin statics suffice (only used for SRV lookup with zeroed state;
#   res.ndots has no effect, documented in the patch).
# - 0003-namespace-linux-unistd: sys/unistd.h is glibc-only; musl
#   covers this TU through unistd.h (nothing exclusive is used).
# - 0004-groups-musl-grent-pwent-r: getgrent_r/getpwent_r are absent
#   from musl; extend the existing __APPLE__ plain-getgrent/getpwent
#   fallback to non-glibc Linux (blast radius: none, every building
#   platform keeps its path).
# - 0005-macros-w-exitcode: W_EXITCODE is glibc-only; provide glibc's
#   identical construction guarded in src/common/macros.h (covers
#   slurmstepd and srun, which already include it).

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
	# Upstream units are never installed (see configure matrix);
	# prune whatever arrives anyway so only owned definitions ship.
	rm -rf "$PKGDEST/usr/lib/systemd"
	# slurmdbd is owned by recipes/slurm-accounting: prune the binary
	# here (it builds regardless of mysql; only the plugin is gated
	# by it). No MySQL in core, enforced: without-mysql_config must
	# leave no mysql plugin behind. Present means the matrix silently
	# changed, and the build fails here, not on a node.
	rm -f "$PKGDEST/usr/sbin/slurmdbd"
	[ ! -e "$PKGDEST/usr/lib/slurm/accounting_storage_mysql.so" ] || \
		{ echo "ERROR: slurm core payload contains mysql accounting" >&2; return 1; }
	# Generic upstream examples only; never a live cluster config.
	# slurmdbd.conf.example belongs to slurm-accounting.
	install -d -m 0755 "$PKGDEST/etc/slurm"
	for example in cgroup.conf cli_filter.lua job_submit.lua prolog \
			slurm.conf; do
		install -m 0644 "$SRC/etc/$example.example" \
			"$PKGDEST/etc/slurm/$example.example"
	done
	# Dual-init policy: all three daemon definition pairs ship
	# unconditionally; none is enabled or started at install. slurmd
	# carries no required_files (configless-capable); slurmctld
	# requires the live slurm.conf saphira-cluster generates.
	install -D -m 0755 "$RECIPE_DIR/files/slurmd.initd" \
		"$PKGDEST/etc/init.d/slurmd"
	install -D -m 0644 "$RECIPE_DIR/files/slurmd.service" \
		"$PKGDEST/usr/lib/systemd/system/slurmd.service"
	install -D -m 0755 "$RECIPE_DIR/files/slurmctld.initd" \
		"$PKGDEST/etc/init.d/slurmctld"
	install -D -m 0644 "$RECIPE_DIR/files/slurmctld.service" \
		"$PKGDEST/usr/lib/systemd/system/slurmctld.service"
	# sackd is the auth/cred kiosk for login nodes (upstream sackd(8)),
	# unrelated to MariaDB accounting, so it and its definitions are
	# core. Its configless fetch cache defaults to /run/slurm/conf;
	# RUNTIME_DIRECTORY (honored only by sackd) points it at the
	# Saphira runtime root instead, converged by tmpfiles.d/checkpath.
	install -D -m 0755 "$RECIPE_DIR/files/sackd.initd" \
		"$PKGDEST/etc/init.d/sackd"
	install -D -m 0644 "$RECIPE_DIR/files/sackd.service" \
		"$PKGDEST/usr/lib/systemd/system/sackd.service"
	install -D -m 0644 "$RECIPE_DIR/files/sackd.tmpfiles" \
		"$PKGDEST/usr/lib/tmpfiles.d/sackd.conf"
	# Log rotation: the recipe creates /var/log/slurm and the daemons
	# log to files there, so it owns the rotation fragment (no
	# logrotate dependency: the fragment is inert without it).
	install -D -m 0644 "$RECIPE_DIR/files/logrotate.d/slurm" \
		"$PKGDEST/etc/logrotate.d/slurm"
	for p in etc/init.d/slurmd etc/init.d/slurmctld etc/init.d/sackd \
			etc/logrotate.d/slurm \
			usr/lib/systemd/system/slurmd.service \
			usr/lib/systemd/system/slurmctld.service \
			usr/lib/systemd/system/sackd.service \
			usr/lib/tmpfiles.d/sackd.conf \
			usr/sbin/slurmd usr/sbin/slurmstepd \
			usr/sbin/slurmctld usr/sbin/sackd \
			etc/slurm/slurm.conf.example; do
		[ -e "$PKGDEST/$p" ] || \
			{ echo "ERROR: slurm payload is missing $p" >&2; return 1; }
	done
	# Service identity declaration (single owner: this package;
	# slurm-accounting depends on slurm so the identity exists before
	# slurmdbd is installed). slurm:153 is a new Saphira allocation in
	# the 0..199 package range, documented here per namespace policy.
	# State dirs: ctld state (slurm-owned), slurmd spool (root-owned,
	# slurmd runs as root), shared log dir.
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/slurm" \
		"$PKGDEST/usr/share/saphira/accounts.d/slurm"
}
