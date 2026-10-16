#!/bin/sh

pkgname=systemd
pkgver=262
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
pkgrel=6
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
source=https://github.com/systemd/systemd/archive/8cc40e0c5e9234bf45084751ac53b1fbfe70b492.tar.gz
sha256=a8d72c03431860cefaafaa2f8cf6f68bcba817184c3708896e4b65471ab0f9ef

# Init-coupling invariant (dbus dragged PID-1 systemd onto OpenRC Egg
# via a runtime depends): reusable libsystemd ships as systemd-libs
# (+ systemd-dev for the headers/.pc), so library consumers never
# resolve the init package. The libs splits carry no /sbin/init, no
# units, and no accounts fragment - those stay in main only.
subpackages="
    systemd-libs
    systemd-dev
"

# udev owns the shared device-manager payload; this package is its strict
# complement and always runs alongside it.
depends="
    dbus
    kmod
    libucontext
    linux-pam
    saphira-base-accounts
    udev
    xz
"

makedepends="
    acl-dev
    binutils
    bpftool
    clang
    curl-dev
    elfutils-dev
    gcc
    gawk
    gperf
    kmod-dev
    libarchive-dev
    libbpf-dev
    libseccomp-dev
    libucontext-dev
    linux-pam-dev
    saphira-kernel-headers
    lz4-dev
    make
    meson
    ninja
    openssl-dev
    pcre2-dev
    pkgconf
    python-jinja2
    python-pefile
    util-linux-dev
    xz-dev
    zlib-dev
    zstd-dev
"

recipe_build()
{
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
	# Feature-policy pins (audit 2026-10-09): gnutls/bzip2 are
	# type=feature (auto) and Saphira carries neither in makedepends, so
	# today they resolve off by absence; pin disabled so a future
	# transitive -dev can never flip them on silently. utmp needs no
	# pin: upstream forces it off whenever -Dlibc=musl (feature table,
	# 'musl does not support it'). (Option names are lowercase upstream;
	# meson fails closed on unknown options, so a miscased pin breaks
	# the build instead of silently doing nothing.)
	# (Comment lives here, not inside the invocation: a comment line
	# breaks backslash continuation and turns flags into commands.)
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
		-Dtests=false \
		-Dman=disabled \
		-Dpam=enabled \
		-Dldconfig=false \
		-Dgnutls=disabled \
		-Dbzip2=disabled \
		-Dmount-path=/bin/mount \
		-Dumount-path=/bin/umount \
		-Dsulogin-path=/sbin/sulogin \
		-Dagetty-path=/sbin/agetty \
		-Dswapon-path=/sbin/swapon \
		-Dswapoff-path=/sbin/swapoff \
		-Dnologin-path=/sbin/nologin \
		-Dkmod-path=/usr/bin/kmod \
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
	#   man=disabled  queued: no python-lxml recipe; chain is
	#                 python3-dev -> python-lxml -> re-enable man and docs.
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
	#   tests=false   payload-only build: the test suite pulls additional
	#                 introspection dependencies and ships nothing.
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
		usr/lib/libudev.so.1.7.14 \
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
