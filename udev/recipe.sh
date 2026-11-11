#!/bin/sh

pkgname=udev
pkgver=262.2
pkgrel=1
# 262.2: port 261.2 to the shared v262.2 tag tarball (the same revision
# the systemd package builds; Saphira patches rebased and verified
# fuzz-free against pristine 262.2). Upstream removed sysvinit-path
# (flag dropped: meson fails closed on unknown options), and the kmod
# assertion no longer greps -q through a pipe (builder pipefail plus an
# early grep exit SIGPIPEs strings on a good binary: proven 141s on two
# r9 builds whose artifact carried the builtin; count form is exact).
# Previous 261.2-r9 state preserved in git history.
# r9: -Dkmod=enabled plus a build-time assertion that the built udevd
# carries the kmod builtin. Without it udevd logs "Unknown builtin
# command 'kmod ...'" for every modalias and no driver ever autoloads
# (proven on Minimer 2026-11-07: new disk booted, i915 present but
# never bound; Egg's own udevadm confirms the builtin missing
# fleet-wide). Silent meson autodetection is never trusted for this:
# the flag fails closed at configure time (which immediately exposed
# the incomplete closure: libkmod needs zlib-dev + zstd-dev, now
# declared), the strings check fails closed at build time.
# r8: SEV1 init contract (2026-10-22): the meson path patch pinned kmod at
# /bin/kmod, which does not exist - the kmod recipe installs /usr/bin/kmod,
# so the shipped udevd carried a dead hotplug-modprobe path. Pinned to the
# owning recipe's path, relative progs resolve under /sbin (every relative
# entry is sbin-class on Saphira), and the payload asserts sbin/init absent
# plus the daemon present (the keep-list skips missing entries silently).
# r6: ship a prebuilt hardware database (lib/udev/hwdb.bin) compiled
# from the staged sources at package build time. The database is
# hardware-independent (a deterministic trie over static .hwdb
# sources), so rebuilding it identically on every fresh machine is
# pure waste - and on a first boot it costs 20-30 seconds while
# udevd waits behind systemd-hwdb-update.service (proven: SaphiraD
# guest showing that job at 19s with no other boot progress).
# With the database current, a fresh image whose /etc/.updated stamp
# (written last by saphira-assemble-rootfs) is newer than /usr skips
# the update via ConditionNeedsUpdate; a later package upgrade still
# refires it exactly once. TimeoutSec is untouched: nothing is hidden,
# the work is simply already done.
# r5: rewrite the upstream 99-systemd.rules sysctl callout to
# the packaged path (merged-usr /lib location does not exist;
# every net add logged a failed callout). Fail closed on drift.
# r7: ship the missing openrc service (/etc/init.d/udev). The package
# carried the daemon, rules and helpers but no init integration, so
# on openrc no udevd ever ran and /dev/disk/* was never populated
# (proven Egg 2026-10-19). Single service by design: trigger and
# settle run in start_post, so no separate trigger/settle units.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Standalone systemd udev device manager"
license="LGPL-2.1-or-later"
origin=udev
repo=main
url=https://systemd.io/
source=https://github.com/systemd/systemd/archive/refs/tags/v262.2.tar.gz
sha256=116432ee9dce9bfef4c7da7963c6de41899ab44197f2876ee99545707a5c7c1f

depends="
    kmod
    libucontext
"

makedepends="
    acl-dev
    gcc
    binutils
    gawk
    gperf
    kmod-dev
    libcap-dev
    libucontext-dev
    saphira-linux-uapi-headers
    make
    meson
    ninja
    pkgconf
    python-jinja2
    util-linux-dev
    zlib-dev
    zstd-dev
"

subpackages="
    $pkgname-dev
"

recipe_build()
{
	meson setup "$BUILDDIR" "$SRC" \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--buildtype=release \
		-Dlibc=musl \
		-Dinitrd=false \
		-Dhibernate=false \
		-Dpam=disabled \
		-Dacl=enabled \
		-Dadm-group=false \
		-Danalyze=false \
		-Dapparmor=disabled \
		-Daudit=disabled \
		-Dbacklight=false \
		-Dbinfmt=false \
		-Dbootloader=disabled \
		-Dbpf-framework=disabled \
		-Ddbus=disabled \
		-Dcoredump=false \
		-Defi=false \
		-Denvironment-d=false \
		-Dgcrypt=disabled \
		-Dgnutls=disabled \
		-Dhostnamed=false \
		-Dkernel-install=false \
		-Dkmod=enabled \
		-Dlibcryptsetup=disabled \
		-Dlibcurl=disabled \
		-Dlibfido2=disabled \
		-Dlibidn2=disabled \
		-Dlogind=false \
		-Dnetworkd=false \
		-Dopenssl=disabled \
		-Dp11kit=disabled \
		-Dpolkit=disabled \
		-Dqrencode=disabled \
		-Dresolve=false \
		-Dseccomp=disabled \
		-Dselinux=disabled \
		-Dsysusers=false \
		-Dtimesyncd=false \
		-Dtmpfiles=false \
		-Dtpm=false \
		-Dukify=disabled \
		-Dutmp=false \
		-Dvconsole=false \
		-Dxkbcommon=disabled \
		-Dhwdb=true \
		-Dman=disabled \
		-Dstandalone-binaries=true \
		-Dstatic-libudev=true \
		-Dtests=false \
		-Dlink-udev-shared=false \
		-Dsplit-bin=false \
		-Drpmmacrosdir=no \
		-Dpamconfdir=no
	ninja -C "$BUILDDIR"
	# The kmod builtin is load-bearing: without it udevd logs
	# "Unknown builtin command 'kmod ...'" for every modalias and no
	# driver ever autoloads (proven on Minimer 2026-11-07: i915
	# present but never bound). -Dkmod=enabled above already fails
	# closed at configure time if libkmod is truly absent; this
	# asserts the built daemon actually carries the builtin, so a
	# silent meson fallback can never ship again.
	# The daemon is the udevadm multicall binary (packaged as
	# /usr/bin/udevadm; /lib/systemd/systemd-udevd is a symlink
	# selecting daemon behaviour by argv[0]). There is no separate
	# systemd-udevd file to find.
	udevd_bin=$(find "$BUILDDIR" -maxdepth 1 -type f -name udevadm | head -1)
	[ -n "$udevd_bin" ] || {
		printf 'udev: built udevadm not found\n' >&2
		return 1
	}
	printf 'udev: asserting kmod builtin in %s\n' "$udevd_bin" >&2
	# Builder shells run with pipefail: grep -q exits on the first
	# match, SIGPIPEs strings mid-stream, and the pipeline fails 141 on
	# a binary that carries the builtin (proven twice on r9). Count
	# instead: grep -c drains the pipe, and the count is exact.
	if command -v strings >/dev/null 2>&1; then
		kmod_count=$(strings "$udevd_bin" | grep -c -x 'kmod' || true)
		[ "$kmod_count" -ge 1 ] || {
			printf 'udev: built udevd lacks the kmod builtin (strings matches: %s)\n' "$kmod_count" >&2
			return 1
		}
	else
		printf 'udev: strings unavailable, kmod builtin unasserted\n' >&2
		return 1
	fi
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C "$BUILDDIR" install

	# Reduce the staged tree to exactly the shared device-manager payload:
	# udevadm, the standalone daemon, hwdb, rules and libudev.  Everything
	# else the source builds belongs to the systemd package; the whitelist
	# keeps that boundary explicit as upstream layout moves.
	# Openrc service (see files/): installed before the whitelist
	# shuffle below so the kept-tree move preserves it.
	install -D -m 0755 "$RECIPE_DIR/files/udev.initd" \
		"$PKGDEST/etc/init.d/udev"
	kept="$PKGDEST.keep"
	mkdir "$kept"
	for item in \
		bin/udevadm \
		usr/bin/udevadm \
		usr/bin/systemd-hwdb \
		lib/systemd/systemd-udevd \
		lib/udev \
		etc/udev \
		etc/init.d/udev \
		usr/lib/libudev.so* \
		usr/lib/libudev.a \
		usr/include/libudev.h \
		usr/lib/pkgconfig/libudev.pc \
		usr/share/pkgconfig/udev.pc
	do
		for src in "$PKGDEST"/$item; do
			if [ -e "$src" ] || [ -L "$src" ]; then
				dest=$kept/${src#"$PKGDEST"/}
				mkdir -p "$(dirname "$dest")"
				cp -a "$src" "$dest"
			fi
		done
	done
	rm -rf -- "$PKGDEST"
	mv "$kept" "$PKGDEST"
	# Non-usrmerged RUN path: upstream 99-systemd.rules invokes the
	# per-device sysctl helper at its merged-usr location, which does
	# not exist on Saphira (every net add logs a failed callout).
	# Rewrite to the packaged path; fail closed if upstream moves it.
	if grep -q 'RUN+="/lib/systemd/systemd-sysctl ' \
		"$PKGDEST/lib/udev/rules.d/99-systemd.rules"; then
		sed -i 's#RUN+="/lib/systemd/systemd-sysctl #RUN+="/usr/lib/systemd/systemd-sysctl #' \
			"$PKGDEST/lib/udev/rules.d/99-systemd.rules"
	fi
	grep -q 'RUN+="/usr/lib/systemd/systemd-sysctl ' \
		"$PKGDEST/lib/udev/rules.d/99-systemd.rules" || {
		echo "ERROR: 99-systemd.rules sysctl callout path not found" >&2
		return 1
	}
	# Prebuilt hardware database (see r6 header): compile the staged
	# sources with the just-built standalone tool, rooted at the
	# package staging area so only shipped sources are read. --usr
	# selects UDEVLIBEXECDIR (/lib/udev on Saphira) for the output,
	# which is exactly where the running udevd looks the database up.
	hwdb_tool=$(find "$BUILDDIR" -name systemd-hwdb -type f | head -1)
	test -n "$hwdb_tool" && test -x "$hwdb_tool" || {
		echo "ERROR: just-built systemd-hwdb not found in $BUILDDIR" >&2
		return 1
	}
	"$hwdb_tool" --root="$PKGDEST" --usr update || {
		echo "ERROR: hwdb prebuild failed" >&2
		return 1
	}
	test -s "$PKGDEST/lib/udev/hwdb.bin" || {
		echo "ERROR: prebuilt hwdb.bin missing or empty" >&2
		return 1
	}
	# NOTE: this must be an if-statement, not a trailing `grep &&`
	# guard: under set -eu a trailing grep that (correctly) finds
	# nothing returns 1 and fails the whole build with no message
	# (proven: udev r5 failed silently exactly this way).
	if grep -q 'RUN+="/lib/systemd/' \
		"$PKGDEST/lib/udev/rules.d/99-systemd.rules"; then
		echo "ERROR: merged-usr RUN path remains in 99-systemd.rules" >&2
		return 1
	fi
	# SEV1 containment (2026-10-22): the upstream init-symlink layout
	# (patches/0002 retargets its install dir) must never reach the
	# payload, and the daemon itself must be present - the keep-list
	# above silently skips missing entries, so an absent daemon would
	# ship a daemon-less package with no error.
	if [ -e "$PKGDEST/sbin/init" ] || [ -L "$PKGDEST/sbin/init" ]; then
		echo "ERROR: sbin/init must not ship in the udev payload" >&2
		return 1
	fi
	test -x "$PKGDEST/lib/systemd/systemd-udevd" || {
		echo "ERROR: packaged udev daemon missing: lib/systemd/systemd-udevd" >&2
		return 1
	}
	# Stage1-leak guard (2026-10-19 fossil incident): a clean
	# native build must never embed /saphirabuild stage paths.
	if grep -rqF '/saphirabuild/' "$PKGDEST"; then
		echo "ERROR: staged payload leaks /saphirabuild stage path" >&2
		return 1
	fi
}
