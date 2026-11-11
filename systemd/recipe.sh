#!/bin/sh

pkgname=systemd
pkgver=262.2
# 262.2 series: shared v262.2 tag tarball with the udev package (both
# build the same revision; Saphira patches rebased and verified
# fuzz-free against pristine 262.2; the 262 pin was a detached commit
# whose option set is identical, so this is strictly the maintenance
# delta). Previous 262-r8 state preserved in git history.
# 262 series: pinned to the v262 release commit (branch tip carried an
# accidental docs/CNAME file), rebased Saphira patches, -Dldconfig=false
# retained. Previous 261.2-r17 state preserved in git tag systemd-261.2-r17.
# r9: sysusers-native identities (reverts r8's fragment census, which
# duplicated upstream declarations and drifted): meson pins five IDs,
# files/sysusers-static-ids.patch pins oom/coredump, post-install runs
# systemd-sysusers. Legacy sidecar removed with the census (a lone
# sidecar is incoherent); stale dynamic IDs need manual userdel.
# r2: drop usr/lib/udev/hwdb.d/20-usb-vendor-model.hwdb (hwdata owns it:
# hwdata vendors usb.ids and generates the fragment; dual ownership fails
# the repository gate). Payload change, r1 never published, r2.
# r3: pin split-layout helper paths (262 removed split-usr; merged
# defaults broke every mount unit and emergency sulogin). Payload change.
# r4: native split-FHS PID1 (upstream 262 installs no /sbin/init: its only
# init installation is the usr/sbin merged-usr symlink, which the kernel
# never tries and Saphira does not ship. The 0ece176 grub init= mitigation
# rested on a bad assumption - that the 261 sbin/init symlink would survive
# upgrade. A package must never depend on a file belonging to the version
# it replaces remaining behind; the clean transition deletes it, which is
# exactly what exposed this. Payload change: real 0755 copy of
# usr/lib/systemd/systemd at sbin/init, usr/sbin/init removed,
# -Dsplit-bin=true pinned explicitly).
# r6: systemd-network UID back to 127 (reclaims the canonical ID
# through the documented same-lineage path); env-drop and pam-dev
# fixes retained. Payload vs r4: those two fixes only. (r5's 147
# experiment: seniority re-examined - systemd holds 127 continuously
# since 261.2-r5, polkit claimed it 2026-10-12 - and the hatched
# tombstone reserves 127 for the systemd lineage eternally. polkitd
# vacates to 156 in polkit r2. r5 stays published in hatchling as
# superseded history.)
# r5: drop usr/lib/environment.d/99-environment.conf (upstream shim
# linking ../../../etc/environment, which no Saphira package creates:
# a dangling link in every clean root. Same strict-complement rule as
# the hwdb fragment: do not ship paths whose target nobody owns).
# Also makedepends linux-pam -> linux-pam-dev (the pam r4 -dev split
# moved the headers; same breakage shadow already hit).
# And -Dsystemd-network-uid 127 -> 147: REVERTED (see r6 above).
pkgrel=2
# r7: runtime depends on libseccomp: shipped units set
# SystemCallFilter=bpf/perf_event_open/... and without the library
# those filters are silently ignored ("libseccomp is not available",
# proven on Minimer 2026-11-07) - a quiet sandbox weakening. Payload
# change (metadata only, no binaries).
# r8: runtime depends on libbpf: the build enables -Dbpf-framework
# (libbpf-dev in makedepends links it in) but nothing declared the
# runtime library, so every boot warned "Neither libbpf.so.1 nor
# libbpf.so.0 are installed" and cgroup BPF features stayed disabled
# (Minimer 2026-11-07). Payload change (metadata only, no binaries).
# r17: ldconfig disabled (musl has no ldconfig workflow): -Dldconfig=false
# so neither units/ldconfig.service nor its sysinit.target.wants link is
# installed. Payload change, bumps.
# r13: PAM enabled (linux-pam 1.7.2 now in tree): logind and friends
# link libpam for real session handling. Payload change, bumps.
# r12: unmerged identity + split bus address (memory.vm2.uk
# logind restart-loop: sd-bus default pointed at merged /run/dbus
# while the daemon binds /var/run/dbus; status now carries
# always-on saphira-unmerged alongside the truthful upstream
# flags). Payload change, revision bumps.
# (hotfix 261.2-r10/r11 adopted: split-/run + native-identity semantics
# live on in the 262 line above; no 261.2 downgrade.)
# r10: split-/run patch (PID 1, tmpfiles, D-Bus API and taint no
# longer rewrite/reject /var/run; var.conf alias line removed).
# Payload change, revision bumps.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="System and service manager"
license="LGPL-2.1-or-later"
origin=systemd
repo=main
url=https://systemd.io/
source=https://github.com/systemd/systemd/archive/refs/tags/v262.2.tar.gz
sha256=116432ee9dce9bfef4c7da7963c6de41899ab44197f2876ee99545707a5c7c1f

# Init-coupling invariant (dbus dragged PID-1 systemd onto OpenRC Egg
# via a runtime depends): reusable libsystemd ships as systemd-libs
# (+ systemd-dev for the headers/.pc), so library consumers never
# resolve the init package. The libs splits carry no /sbin/init, no
# units, and no accounts fragment - those stay in main only.
# Manual pages ship as systemd-doc (optional at install time, present
# in the repository): no rebuilding a distribution to read them.
subpackages="
    systemd-libs
    systemd-dev
    systemd-doc
"

# udev owns the shared device-manager payload; this package is its strict
# complement and always runs alongside it.
# cryptsetup-libs: systemd-cryptsetup links libcryptsetup.so.12 (built
# with libcryptsetup=enabled deliberately); without the dep the helper
# dies at exec on cryptsetup-less systems (proven Minimer 2026-11-08).
# kbd is deliberately NOT here: loadkeys is an image intention (it
# belongs in the systemd image profiles), not a dependency of the
# init system itself.
depends="
    cryptsetup-libs
    dbus
    kmod
    libbpf
    libseccomp
    libucontext
    linux-pam
    saphira-base-accounts
    udev
    xz
"

# libucontext: libsystemd.so.0 links it directly (per-object DT_NEEDED,
# proven Minimer 2026-11-08); a standalone systemd-libs install without
# it breaks every libsystemd consumer (dbus links it). Declared on the
# -libs split itself via depends_libs, never on main.
depends_libs="libucontext"

makedepends="
    acl-dev
    binutils
    bpftool
    bzip2-dev
    clang
    cryptsetup-dev
    curl-dev
    docbook-xml
    docbook-xsl-nons
    elfutils-dev
    gcc
    gawk
    gperf
    gnutls-dev
    kmod-dev
    libarchive-dev
    libbpf-dev
    libseccomp-dev
    libtasn1-dev
    libucontext-dev
    libxml2
    libxslt
    linux-pam-dev
    lvm2-dev
    saphira-linux-uapi-headers
    lz4-dev
    make
    meson
    musl-fts
    musl-obstack
    nettle-dev
    ninja
    openssl-dev
    pcre2-dev
    pkgconf
    python-jinja2
    python-lxml
    python-pefile
    python3
    tzdata
    util-linux-dev
    xz-dev
    zlib
    zlib-dev
    zstd-dev
"

recipe_build()
{
	# Catalog bridge (strace-proven 2026-11-07): this tree's libxml2
	# looks for its DEFAULT catalog at /usr/etc/xml/catalog (a path
	# that cannot exist - /usr/etc is forbidden in payloads), while
	# the distribution keeps the real chain at /etc/xml/catalog.
	# Every explicit-path probe (xmlcatalog CLI, test -f) passes
	# while xsltproc --nonet fails, because only the default path
	# is consulted. Point it at the real chain for the whole build.
	# (Whether the compiled default deserves a libxml2 rebuild of
	# its own is a separate core-library decision, not this port.)
	export XML_CATALOG_FILES=/etc/xml/catalog
	# Feature policy: intended features are enabled explicitly with their
	# dependencies declared in makedepends, never left to environment-
	# dependent auto-detection.
	# The two static sysusers confs (oom, coredump) have no meson ID
	# knob, so their fixed IDs arrive via patch (fails closed on
	# upstream drift); the five templated ones pin below.
	patch -d "$SRC" -Np1 -i "$RECIPE_DIR/files/sysusers-static-ids.patch"
	# Split-/run layout: upstream rewrites /var/run to /run in unit
	# parsing (Listen*, PIDFile), transient-unit properties, and
	# tmpfiles entries, taints non-symlink /var/run, and recreates
	# the alias via tmpfiles.d/var.conf. Saphira keeps both real:
	# the patch neuters the rewrites, drops the taint and the alias
	# line, touching no genuine systemd-owned /run path (fails
	# closed on upstream drift like the IDs patch).
	patch -d "$SRC" -Np1 -i "$RECIPE_DIR/files/saphira-split-run.patch"
	# Unmerged identity + split bus address (applies after the
	# split-run patch; taint hunk contexts assume its var-run
	# removal): the sd-bus client default moves to the daemon's
	# real /var/run/dbus address (logind restart-loops otherwise),
	# and an always-on saphira-unmerged taint names the layout.
	patch -d "$SRC" -Np1 -i "$RECIPE_DIR/files/saphira-unmerged.patch"
	# musl DT_NEEDED is a bare "libc.so" (readelf-proven), which the
	# ABI gate's allowlist misses (it knows libc.so.* and the
	# libc.musl- loader name only): without this every object fails
	# the gate. Test-harness-only change, nothing shipped.
	patch -d "$SRC" -Np1 -i "$RECIPE_DIR/files/saphira-test-link-abi-musl-libc.patch"
	# Sandbox test exclusions live in the harness, not on the command
	# line: seven tests need privilege/devices/identity the rootless
	# namespace cannot provide (see the test-env comment below for
	# each reason). Registration skipped, executables still built;
	# positional test selection is avoided entirely (it trips an
	# unreproducible matcher error at this scale).
	patch -d "$SRC" -Np1 -i "$RECIPE_DIR/files/saphira-test-sandbox-exclusions.patch"
	# Non-usrmerged default PATH: /sbin and /bin are real directories
	# holding half the toolset (coreutils --bindir=/bin), but the
	# split-/usr default omits them, blinding find_executable() to
	# every /bin|/sbin helper. Payload change; fails closed on drift.
	patch -d "$SRC" -Np1 -i "$RECIPE_DIR/files/saphira-default-path-split-bin.patch"
	# No-cryptsetup guards (interim accommodation from the port,
	# now TRANSPARENT: libcryptsetup is present, HAVE_LIBCRYPTSETUP
	# compiles the real helpers and the guards are inert pass-throughs.
	# Kept because the #if structure is still the correct shape for
	# the option, and removal would churn the patch for zero payload
	# change. Fails closed on upstream drift like the rest).
	patch -d "$SRC" -Np1 -i "$RECIPE_DIR/files/saphira-repart-no-cryptsetup.patch"
	# The vendored vmlinux.h is a build input like any other pinned
	# payload: verify it before meson reads it. A header silently altered
	# here would change what the BPF programs bind to at runtime, which is
	# precisely the kind of drift a pin exists to prevent.
	(cd "$RECIPE_DIR/files" && sha256sum -c vmlinux.h.sha256) ||
		{ echo "ERROR: systemd/files/vmlinux.h does not match its sidecar" >&2; return 1; }
	# Split-layout helper paths (262 removed upstream split-usr: every
	# relative -Dxxx-path default now resolves under /usr, where Saphira
	# does not ship these helpers. util-linux lives in /bin and /sbin,
	# kmod in /usr/bin. r2 shipped the merged defaults and no mount unit
	# could execute (/usr/bin/mount missing -> remount-fs failed ->
	# emergency, and emergency itself could not run /usr/sbin/sulogin).
	# Pin every helper Saphira ships; kexec/loadkeys/setfont/quota* are
	# not shipped, so their defaults stay dead paths exactly as on 261.
	# Feature-policy pins: type=feature (auto) options are never left
	# to environment-dependent auto-detection. Backends Saphira ships
	# are enabled explicitly with their dependencies declared in
	# makedepends: gnutls (journal-gateway HTTPS alongside openssl's
	# general crypto), bzip2 (blob codec beside xz/zstd/lz4 - journal,
	# repart, sysext and import paths handle .bz2 either way).
	# libcryptsetup is enabled explicitly: encrypted partitions
	# (repart LUKS/integrity, a legitimate Image Creator capability)
	# are intended Saphira functionality. cryptsetup 2.8.8 is now
	# ported (cryptsetup-dev in makedepends above); before the port
	# this failed closed at configure, naming the missing
	# dependency - which was the trigger for the port, never a
	# reason to drop the flag. Nothing here is disabled to get the
	# build through; a future transitive -dev flipping an unpinned
	# auto option on is a packaging event to declare explicitly,
	# not a silent default. utmp needs no pin:
	# upstream forces it off whenever -Dlibc=musl (feature table,
	# 'musl does not support it'). (Option names are lowercase
	# upstream; meson fails closed on unknown options, so a miscased
	# pin breaks the build instead of silently doing nothing.)
	# (Comment lives here, not inside the invocation: a comment line
	# breaks backslash continuation and turns flags into commands.)
	# Man pages resolve their stylesheet import through the XML catalog
	# chain offline (xsltproc runs --nonet): a missing rewrite fails
	# thousands of targets deep with a bare external-entity error.
	# Resolve the exact import up front with the same libxml2 machinery;
	# a gap fails here, naming the URI, while the fix belongs to the
	# catalog owner (docbook-xsl-nons' installed catalog.xml), never
	# to a network fetch or a vendored stylesheet copy here.
	man_uri='http://docbook.sourceforge.net/release/xsl/current/manpages/docbook.xsl'
	man_resolved=$(xmlcatalog /etc/xml/catalog "$man_uri" 2>/dev/null || true)
	case $man_resolved in
	*/manpages/docbook.xsl) ;;
	*)
		printf 'ERROR: man stylesheet does not resolve offline: %s (got: %s)\n' "$man_uri" "$man_resolved" >&2
		return 1
		;;
	esac
	# Resolution alone is not proof: a catalog rewrite to a relative
	# or otherwise unopenable location passes the textual match while
	# xsltproc fails thousands of targets deep (proven 2026-11-07:
	# rewritePrefix "./" resolved textually but never opened). The
	# rewritten target must exist in this build root.
	man_file=$man_resolved
	case $man_file in
	file://*) man_file=${man_file#file://} ;;
	esac
	[ -f "$man_file" ] || {
		printf 'ERROR: man stylesheet resolves to a missing file: %s (from: %s)\n' "$man_file" "$man_resolved" >&2
		return 1
	}
	meson setup "$BUILDDIR" "$SRC" \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--buildtype=release \
		-Dsplit-bin=true \
		-Dlibc=musl \
		-Dacl=enabled \
		-Dblkid=enabled \
		-Dhibernate=true \
		-Dinitrd=true \
		-Dlibcurl=enabled \
		-Dlz4=enabled \
		-Dopenssl=enabled \
		-Dseccomp=enabled \
		-Dxz=enabled \
		-Dzstd=enabled \
		-Dtests=true \
		-Dman=enabled \
		-Dpam=enabled \
		-Dldconfig=false \
		-Dgnutls=enabled \
		-Dbzip2=enabled \
		-Dlibcryptsetup=enabled \
		-Dmount-path=/bin/mount \
		-Dumount-path=/bin/umount \
		-Dsulogin-path=/sbin/sulogin \
		-Dagetty-path=/sbin/agetty \
		-Dswapon-path=/sbin/swapon \
		-Dswapoff-path=/sbin/swapoff \
		-Dnologin-path=/sbin/nologin \
		-Dkmod-path=/usr/bin/kmod \
		-Dfallback-default-target=multi-user.target \
		-Dbpf-framework=enabled \
		-Dbpf-compiler=clang \
		-Dvmlinux-h=provided \
		-Dvmlinux-h-path="$RECIPE_DIR/files/vmlinux.h" \
		-Dsystemd-journal-gid=131 \
		-Dsystemd-network-uid=127 \
		-Dsystemd-resolve-uid=128 \
		-Dsystemd-timesync-uid=129 \
		-Dsystemd-imds-uid=145

	# Explicit non-default states and their recorded reasons:
	#   man=enabled     manual pages build (xsltproc + docbook chain +
	#                 python-lxml for the indices, all declared above)
	#                 and ship as systemd-doc: documentation stays
	#                 optional at install time without being absent
	#                 from the repository. Upstream default is disabled.
	#   pam=enabled   linux-pam 1.7.2 landed: logind/homed get real
	#                 PAM session handling (no pam.d configs shipped
	#                 yet - that is a follow-up, not this flag).
	#   ldconfig=false
	#                 Saphira is musl: there is no ldconfig, no
	#                 ld.so.cache workflow, and no reason for
	#                 ldconfig.service to execute. Upstream installs and
	#                 statically enables it (sysinit.target.wants/) unless
	#                 this flag is false, and recipe_install fails closed
	#                 if either path ever reappears.
	#   fallback-default-target=multi-user.target
	#                 Upstream default is graphical.target, which cannot
	#                 exist on headless Saphira; a missing default.target
	#                 would fall through a dead link before rescue.
	#                 multi-user always exists and keeps rescue as the
	#                 final endpoint, as on 262.
	#   tests=true    explicit per feature policy (never leave a
	#                 tri-state to silent default): unit tests are
	#                 load-bearing validation for a musl + split-layout
	#                 port, exactly where upstream tests earn their keep.
	#                 slow-tests and dlopen-tests stay at their upstream
	#                 defaults (off); fuzz regression tests run at
	#                 theirs (on). install-tests stays off so no test
	#                 binary can ship (payload invariant, not trust).
	#   bpf-framework=enabled
	#                 REQUIRED, not optional: systemd-nsresourced refuses to
	#                 hand out a managed user namespace without a BPF LSM
	#                 lockdown, and fails closed. nsresourcework.c installs
	#                 the userns-restrict program and returns its error with
	#                 no fallback; userns-restrict.c returns EOPNOTSUPP when
	#                 HAVE_VMLINUX_H is undefined. That is the whole reason
	#                 rootless systemd-nspawn -- which selects
	#                 USER_NAMESPACE_MANAGED by default whenever getuid() != 0
	#                 -- failed with "Failed to allocate user namespace with
	#                 64K users: Not supported". Disabling this again would
	#                 restore that failure, silently and at runtime.
	#   bpf-compiler=clang
	#                 The BPF programs need CO-RE and BPF maps, which the
	#                 gcc path cannot build. This also requires clang to have
	#                 been built with the BPF backend, which comes from llvm
	#                 (see llvm's LLVM_TARGETS_TO_BUILD) AND from clang's own
	#                 build: a clang linked against a BPF-capable libLLVM
	#                 still fails -target bpf unless it was rebuilt too.
	#   vmlinux-h=provided
	#                 Deliberately NOT 'auto'. With 'auto', meson falls back
	#                 to generating vmlinux.h from the BUILD HOST's live
	#                 /sys/kernel/btf/vmlinux, so the compiled BPF programs
	#                 would silently depend on whichever kernel happened to
	#                 be running the build. 'provided' pins the header that
	#                 this package vendors, which keeps the build
	#                 reproducible and host-independent.
	#
	# The vendored vmlinux.h was generated from the BTF of the Saphira
	# 7.2.2 kernel this generation builds, on a host booted from that
	# kernel, using systemd's own command:
	#   bpftool btf dump file /sys/kernel/btf/vmlinux format c
	# It is verified against its sidecar in recipe_build, so a tampered or
	# truncated header cannot quietly change what the BPF programs bind to.
	# initrd/hibernate are intentional Saphira states (true): both are
	# dependency-free upstream booleans kept on deliberately.
	ninja -C "$BUILDDIR"
	# Validation is part of the build, not a separate chore: Saphira
	# builds systemd against musl with its own layout, which is
	# precisely where upstream tests earn their keep.
	# Test environment the sandbox does not provide (upstream CI has
	# all of it; the build root is a minimal dependency closure):
	# /var/tmp is created here (seven tests mkdtemp under it; the
	# seed is the right long-term home for that directory, noted
	# separately). TZ is deliberately NOT exported: meson builds a
	# fixed per-test env that drops the parent (TZ= appeared zero
	# times in a full-suite log), and every timezone test sets TZ
	# itself - tzdata in makedepends supplies the zoneinfo it reads.
	# Named exclusions, one by one with reasons - never a blanket skip
	# (integration tests join this list by suite; a name the suite
	# flag would also drop is a hard error, so one filter owns all):
	#   test-mount-util   bind-remount of /run needs privilege the
	#                     userns build cannot grant (EPERM, proven).
	#   test-loop-util    loop-device setup needs privilege/dev nodes
	#                     the sandbox cannot provide (proven).
	#   test-namespace    idmapping support absent in the sandbox
	#                     userns (proven).
	#   test-data-fd-util PR_SET_MM_ARG_START denied by the sandbox
	#                     seccomp profile (EOPNOTSUPP, proven).
	#   test-chase        needs /etc/os-release, which no build root
	#                     carries (product identity ships at image
	#                     time via saphira-release, never in a build
	#                     closure; proven ENOENT).
	#   test-os-util      same os-release absence (proven).
	#   test-specifier    same os-release absence (%B os build ID
	#                     dies at test-specifier.c:148; excluding now
	#                     avoids whack-a-mole over every other
	#                     identity-derived specifier).
	mkdir -p /var/tmp
	# Integration tests spawn full VMs (TEST-xx images) and cannot run
	# in a package build namespace; the seven sandbox-bound tests above
	# are excluded by name in files/saphira-test-sandbox-exclusions.patch
	# (registration skipped, executables still built). Plain suite
	# exclusion plus no positional args: positional selection trips an
	# unreproducible matcher error at this scale, so names are never
	# passed on the command line.
	meson test -C "$BUILDDIR" --print-errorlogs --no-stdsplit --quiet \
		--no-suite integration-tests --timeout-multiplier 3
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C "$BUILDDIR" install

	# Strict-complement rule: remove exactly the paths owned by the shared
	# udev package so no file is ever duplicated between the two.  Keep this
	# list mirroring the udev recipe whitelist; units under
	# /usr/lib/systemd stay here even when they reference the udev daemon.
	for path in \
		bin/udevadm \
		usr/bin/udevadm \
		usr/bin/systemd-hwdb \
		lib/systemd/systemd-udevd \
		lib/udev \
		etc/udev \
		usr/include/libudev.h \
		usr/lib/libudev.a \
		usr/lib/libudev.so \
		usr/lib/libudev.so.1 \
		usr/lib/libudev.so.1.7.15 \
		usr/lib/pkgconfig/libudev.pc \
		usr/share/pkgconfig/udev.pc; do
		rm -rf -- "$PKGDEST"/$path
	done
	# Same rule against hwdata: upstream systemd generates
	# 20-usb-vendor-model.hwdb from the USB ID database, but hwdata is
	# the package that vendors usb.ids and generates that fragment, so
	# hwdata owns the installed path. systemd must not ship its own
	# copy (different snapshot, same path - the repository gate refuses
	# dual ownership). systemd-hwdb update still compiles it: it reads
	# every fragment in /usr/lib/udev/hwdb.d regardless of owner.
	for path in \
		usr/lib/udev/hwdb.d/20-usb-vendor-model.hwdb \
		usr/lib/environment.d/99-environment.conf; do
		rm -rf -- "$PKGDEST"/$path
	done
	# Account layer is sysusers-native, not a fragment census: the
	# shipped sysusers.d confs carry Saphira-pinned fixed IDs (five
	# via meson -D above, oom/coredump via the static-ids patch), and
	# makepkg generates post-install/post-upgrade running
	# systemd-sysusers from the fragment's sysusers stanza. The
	# fragment ships main-only alongside the confs it governs.
	# r5: fragment added + xz enabled (payload changes, revision bumps).
	# r6: systemd-libs/systemd-dev splits (libsystemd out of the init
	# package; fragment stays main-only).
	# r7: ships systemd.legacy (r6 built from a pre-sidecar tree: the
	# sidecar commit landed mid-build, so receipts knew legacy while
	# the payload did not - payload presence now regression-tested).
	# r8: fragment briefly duplicated upstream IDs (drift-prone census).
	# r9: sysusers stanza replaces the census; sidecar removed with it
	# (lone sidecars are incoherent - stale dynamic IDs need manual
	# userdel, there is no automated migration without a census).
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/systemd" \
		"$PKGDEST/usr/share/saphira/accounts.d/systemd"
	# musl has no ldconfig: fail the build rather than ship a unit that
	# can only fail at boot. This converts the -Dldconfig=false
	# assumption into a packaging invariant against future upstream
	# changes to the option, the unit name, or the enablement path.
	for path in \
		usr/lib/systemd/system/ldconfig.service \
		usr/lib/systemd/system/sysinit.target.wants/ldconfig.service; do
		if [ -e "$PKGDEST/$path" ] || [ -L "$PKGDEST/$path" ]; then
			echo "ERROR: musl build shipped $path" >&2
			return 1
		fi
	done
	# Native split-FHS PID1 (upstream 262 removed split-usr: the daemon
	# installs only at usr/lib/systemd/systemd and the sole init link is
	# the merged-usr usr/sbin/init symlink, which the kernel never
	# executes and Saphira neither needs nor supports. The kernel's
	# hardcoded search needs a real executable at /sbin/init).
	# Closure proof (262-r3 vs 261.2-r17 payloads, 2026-10-09): INTERP
	# identical (/lib/ld-musl-x86_64.so.1); NEEDED identical shape
	# (versioned libsystemd-core/shared + libc, RPATH /usr/lib/systemd
	# exactly as on 261); PID1 baked paths only /bin/sh plus its own
	# /usr/lib/systemd/*; no unit ExecStart points outside /usr or at an
	# unrestored /lib path. A byte copy therefore introduces no new
	# dependency - the /usr/lib/systemd RPATH already exists on 261.
	# Copy, never symlink: compat links to the merged layout are banned.
	# No /lib/systemd/systemd copy: nothing in 262 references it.
	if [ ! -f "$PKGDEST/usr/lib/systemd/systemd" ] || [ -L "$PKGDEST/usr/lib/systemd/systemd" ]; then
		echo "ERROR: upstream PID1 binary missing or not a real file" >&2
		return 1
	fi
	rm -f -- "$PKGDEST/usr/sbin/init"
	install -D -m 0755 "$PKGDEST/usr/lib/systemd/systemd" "$PKGDEST/sbin/init"
	# Fail closed on the contract: sbin/init real, usr/sbin/init gone.
	if [ -L "$PKGDEST/sbin/init" ]; then
		echo "ERROR: sbin/init must be a real executable, not a symlink" >&2
		return 1
	fi
	if [ -e "$PKGDEST/usr/sbin/init" ] || [ -L "$PKGDEST/usr/sbin/init" ]; then
		echo "ERROR: merged-usr usr/sbin/init must not ship" >&2
		return 1
	fi
}
