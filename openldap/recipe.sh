#!/bin/sh

pkgname=openldap
pkgver=2.6.15
# r1: single recipe, single configure, single make. Full client +
# server family in one build: tools, shared runtimes, slapd with the
# complete dependency-available backend/overlay set, upstream systemd
# unit plus Saphira OpenRC init. No second producer recipe, no
# double compilation (packaging limitation, documented below).
# r2: slapd runtime /run/slapd -> /var/run/slapd (example config,
# initd, unit drop-in, fhs.d fragment). Payload change, revision bumps.
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='OpenLDAP directory server, client libraries and tools'
license='OLDAP-2.8'
origin=openldap
repo=saphira
url=https://www.openldap.org/
source=https://www.openldap.org/software/download/OpenLDAP/openldap-release/openldap-2.6.15.tgz
sha256=bc91225dbfc50354033b1303bc91d1a7f6ddd1dc32fac950d79c28fe66d6bca8

# Capability matrix (verified against configure.ac in this tree):
#   enabled explicitly (dep-free, normal upstream capability):
#     backends dnssrv ldap meta asyncmeta null passwd sock, back-perl
#       (perl 5.44.0 published; essential Saphira infrastructure),
#     overlays accesslog auditlog autoca collect constraint dds deref
#     dyngroup dynlist homedir memberof nestgroup otp ppolicy
#     proxycache refint remoteauth rwm seqmod sssvlv translucent
#     unique valsort, pw-argon2 as a loadable module
#     (--enable-argon2=yes requires --enable-modules: upstream builds
#     the scheme only as a module. Module infrastructure needs
#     libltdl, which is packaged (libtool/libtool-dev) - a legitimate
#     dependency, so the capability stays on.)
#   upstream default kept (no flag added, nothing trimmed):
#     mdb relay syncprov (default yes), monitor ldif (always built),
#     retcode (testing-only overlay, not production capability)
#   blocked by unavailable dependencies (follow-up ports, not silent
#   exclusions): sql -> BLOCKED_BY_unixodbc, wt -> BLOCKED_BY_wiredtiger,
#     cyrus-sasl (auto-resolves off; highest-priority follow-up, broad
#     authentication infrastructure)
#   left at upstream default (separate daemon surface, author decision
#   on demand): balancer/lloadd
#   invalid upstream: --with-odbc takes auto|iodbc|unixodbc|odbc32 only,
#     no off value exists; default auto probes, finds nothing, stays off.
#
# Packaging limitation (reported, not worked around): the worker splits
# only -dev/-doc/-libs, and a -libs split carries a parent-version pin
# (verified live: gcc-libs depends gcc=...), which would drag the full
# server+tools payload onto every libldap consumer. This revision
# therefore ships one monolithic openldap + openldap-dev; libldap
# consumers transiently pull slapd (disk cost only, nothing runs
# unconfigured). A future splitter extension with pin-free functional
# outputs is required for the true four-output family.
# Upstream systemd support is protocol-native, not linked: slapd
# speaks the notify protocol through OpenLDAP's own bundled
# sd-notify.h, so no libsystemd DT_NEEDED entry exists by design and
# no systemd-libs runtime dependency is declared. systemd-dev stays
# in makedepends so systemdsystemunitdir detection (unit install
# path) resolves reliably instead of depending on rootfs layout.
depends="
    libargon2
    libtool
    openssl
    perl
"

makedepends="
    binutils
    gcc
    groff
    libargon2-dev
    libtool-dev
    make
    openssl-dev
    perl
    pkgconf
    systemd-dev
"

subpackages="$pkgname-dev"

recipe_build()
{
	./configure \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--with-tls=openssl \
		--with-threads=posix \
		--with-argon2=libargon2 \
		--enable-dnssrv --enable-ldap --enable-meta \
		--enable-asyncmeta --enable-null --enable-passwd \
		--enable-perl --enable-sock \
		--enable-accesslog --enable-auditlog --enable-autoca \
		--enable-collect --enable-constraint --enable-dds \
		--enable-deref --enable-dyngroup --enable-dynlist \
		--enable-homedir --enable-memberof --enable-nestgroup \
		--enable-otp --enable-ppolicy --enable-proxycache \
		--enable-refint --enable-remoteauth --enable-rwm \
		--enable-seqmod --enable-sssvlv --enable-translucent \
		--enable-unique --enable-valsort \
		--enable-modules \
		--enable-argon2 \
		--disable-static
	# tests/ is never entered (server test suite, not payload).
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	for dir in include libraries clients servers; do
		make -C "$dir" DESTDIR="$PKGDEST" install
	done
	make -C doc DESTDIR="$PKGDEST" install
	find "$PKGDEST" -name '*.la' -delete
	# Upstream systemd integration ships in-tree and installs
	# conditionally on systemdsystemunitdir detection. Assert it
	# landed; fall back to installing upstream's own unit file.
	if [ ! -f "$PKGDEST/usr/lib/systemd/system/slapd.service" ]; then
		install -D -m 0644 "$SRC/servers/slapd/slapd.service" \
			"$PKGDEST/usr/lib/systemd/system/slapd.service"
	fi
	# The unit references this EnvironmentFile; upstream does not
	# create it, and the unit fails without it.
	install -D -m 0644 "$RECIPE_DIR/files/sysconfig-slapd" \
		"$PKGDEST/etc/sysconfig/slapd"
	# Saphira OpenRC init alongside the native unit: same daemon
	# (/usr/libexec/slapd), same config (/etc/openldap/slapd.conf).
	install -D -m 0755 "$RECIPE_DIR/files/slapd.initd" \
		"$PKGDEST/etc/init.d/slapd"
	# Saphira runtime-path drop-in for the upstream unit (left
	# byte-identical): ensures /var/run/slapd with the service
	# identity before the daemon starts.
	install -D -m 0644 "$RECIPE_DIR/files/slapd-saphira.conf" \
		"$PKGDEST/usr/lib/systemd/system/slapd.service.d/saphira.conf"
	# Server config template only: the operator owns
	# /etc/openldap/slapd.conf; never ship a populated default.
	for conf in "$PKGDEST"/etc/openldap/slapd.conf \
		"$PKGDEST"/etc/openldap/slapd.conf.default; do
		if [ -f "$conf" ]; then
			mv "$conf" "$PKGDEST/etc/openldap/slapd.conf.example"
			break
		fi
	done
	install -m 0644 "$RECIPE_DIR/files/slapd.conf.example" \
		"$PKGDEST/etc/openldap/slapd.conf.example"
	# Client config template only (same policy as the server side).
	if [ -f "$PKGDEST/etc/openldap/ldap.conf" ]; then
		mv "$PKGDEST/etc/openldap/ldap.conf" \
			"$PKGDEST/etc/openldap/ldap.conf.example"
	fi
	install -d -m 0755 "$PKGDEST/usr/share/licenses/openldap"
	install -m 0644 "$SRC/LICENSE" \
		"$PKGDEST/usr/share/licenses/openldap/LICENSE"
	# Payload proof: daemon, one client tool, public headers, unit.
	test -x "$PKGDEST/usr/libexec/slapd" || \
		{ printf 'openldap: slapd missing\n' >&2; exit 1; }
	test -x "$PKGDEST/usr/bin/ldapsearch" || \
		{ printf 'openldap: ldapsearch missing\n' >&2; exit 1; }
	test -f "$PKGDEST/usr/include/ldap.h" || \
		{ printf 'openldap: ldap.h missing\n' >&2; exit 1; }
	test -f "$PKGDEST/usr/lib/systemd/system/slapd.service" || \
		{ printf 'openldap: slapd.service missing\n' >&2; exit 1; }
	# Capability proof: backends and overlays compiled in (-VVV
	# lists static backends/overlays); argon2 ships as a loadable
	# module, proven by its installed object (load via moduleload,
	# see the example config).
	#
	# libldap/liblber ship in this same payload (first native build -
	# no repo provides them yet), so the just-installed library dir
	# must be on the loader path to execute the proof.
	proof_ld_path=$PKGDEST/usr/lib
	for cap in 'mdb' 'relay' 'passwd' 'syncprov' 'ppolicy' 'memberof'; do
		LD_LIBRARY_PATH=$proof_ld_path "$PKGDEST/usr/libexec/slapd" -VVV 2>&1 \
			| grep -i "$cap" > /dev/null || \
			{ printf 'openldap: capability %s missing from slapd\n' "$cap" >&2; exit 1; }
	done
	test -e "$PKGDEST/usr/libexec/openldap/argon2.so" || \
		{ printf 'openldap: argon2 module missing\n' >&2; exit 1; }
	# Linkage proof: the perl backend is honestly linked (notify
	# support is protocol-native per the comment above - asserted
	# via the installed Type=notify unit, not via DT_NEEDED).
	readelf -d "$PKGDEST/usr/libexec/slapd" | grep 'libperl' > /dev/null || \
		{ printf 'openldap: libperl missing from slapd DT_NEEDED\n' >&2; \
		readelf -d "$PKGDEST/usr/libexec/slapd" >&2 || true; exit 1; }
	# Runtime identity declaration: ldap:146 (next free ID in the
	# 0..199 packaged range; verified against accounts.tsv, all
	# accounts.d fragments, and the service-identity migration
	# matrix - 124/125/126 taken, 127..131 and 144/145 sysusers
	# reservations, 132..143 claimed).
	# Cross-check against the active migration before renumbering.
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/openldap" \
		"$PKGDEST/usr/share/saphira/accounts.d/openldap"
	# FHS migration declaration (hotfix/var-packaging-bug-var-run-isnot-run):
	# ldap:146 owns the corrected runtime dir; makepkg runs
	# ensure-fhs after ensure-identity on install/upgrade.
	install -D -m 0644 "$RECIPE_DIR/files/fhs.d/openldap" \
		"$PKGDEST/usr/share/saphira/fhs.d/openldap"
}
