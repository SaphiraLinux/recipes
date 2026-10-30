#!/bin/sh

pkgname=saphira-zfs-userspace
pkgver=2.4.4
pkgrel=6
# r6: boot-proven unit corrections (Minimer 2026-10-26): drop the
# deprecated udev-settle dependency from import-cache/scan, gate all 9
# units on arcstats so builtin and modular kernels both work.
# r5: userspace-only build (--with-config=user): no kernel tree, no
# /input staging, no /usr/src dependency (r4 never published, so r5
# carries the whole fix). Static archives (.a) move to -dev via the
# fixed split, and the upstream functional test suite leaves the payload
# (it was ~20 MiB of fixtures in minimal images). Fail-closed on any
# staged *.ko. Payload change.
# r3: initramfs ZFS-root hook (files/20-zfs-import -> /lib/saphira/
# initramfs/root.d/, suite-proven): imports the pool named by
# root=ZFS= on the cmdline and mounts the dataset at /newroot, else a
# no-op. Inert until a media builder names it in an initramfs.conf
# with `bin zpool`; the default base initramfs is untouched.
# r2: enable upstream systemd integration (Minimer proof: r1 installed
# the OpenRC scripts but no systemd units, so a systemd host had no
# ZFS import/mount/ZED boot lifecycle). Root cause: upstream
# --enable-systemd defaults to `check', which probes `systemctl
# --version' on the BUILD host; the worker root has no systemctl, so
# units, generator, preset and modules-load.d were silently skipped.
# The recipe now passes --enable-systemd=yes with explicit Saphira
# paths (never host-probed), and ships the upstream unit set:
# import-cache/scan + import.target (complementary cache conditions,
# no duplicate import), mount (+@ template), share, zed, zfs.target,
# volume-wait + volumes.target, scrub/trim services + timers (inert
# unless enabled), 50-zfs.preset (inert until `systemctl preset' runs
# - install enables nothing), the zfs-mount-generator (per-dataset
# zfs-load-key@ units; 2.4.4 has no static zfs-load-key.service - the
# generator IS the key machinery), and modules-load.d/zfs.conf.
# Two upstream unit defaults are corrected at install time (r6 note):
# the set is no longer byte-verbatim, deliberately, with the deviation
# and its boot proof recorded in recipe_install, never hidden.
# Dual-init rule: OpenRC scripts keep shipping untouched (sysvinit
# defaults yes); the package must never depend on either init, the
# consumer chooses by enabling. Payload change, revision bumps.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='OpenZFS 2.4.4 userspace (zpool, zfs, libraries, man pages; kernel modules are saphira-zfs-<kver>)'
license=CDDL
origin=saphira-zfs
repo=saphira
url=https://github.com/openzfs/zfs
# Upstream release tarball, vendored (bytes pinned; releases are stable):
# https://github.com/openzfs/zfs/releases/download/zfs-2.4.4/zfs-2.4.4.tar.gz
zfs_sha256=2a3c70d55a37cc71618a95a60e81ad66530201eb118d37741dc92efcf848c8b1

depends="libtirpc curl util-linux openssl"
subpackages="$pkgname-dev"
makedepends="
	binutils
	gcc
	gawk
	kmod
	libtirpc-dev
	curl-dev
	elfutils-dev
	util-linux-dev
	zlib-dev
	openssl-dev
	saphira-linux-uapi-headers
	make
	pkgconf
	python3
"
# Handover from the retired monolithic saphira-zfs (owned userspace,
# man pages and docs): the file gate exempts retired names listed here.
replaces="saphira-zfs"

# Userspace-only: upstream --with-config=user builds cmd/lib/man/tests
# without configuring kernel modules, so this recipe takes no kernel
# tree and no /input staging. It builds with plain
# `buildpkg saphira-zfs-userspace` inside the isolated /build workspace;
# /usr/src is never a build location. Kernel modules live only in the
# per-kernel saphira-zfs-<kver> recipes (self-preparing there).
# Pool compatibility: mounts existing 2.4.1 / 2.4.3 pools; do NOT zpool upgrade.

recipe_build()
{
	# Hook suite first. stdin is nulled: the suite must never consume
	# the builder's stdin.
	sh "$RECIPE_DIR/tests/zfs-import-hook.sh" < /dev/null ||
		{ echo "ERROR: zfs-import-hook suite failed" >&2; return 1; }
	export TAR_OPTIONS=--no-same-owner
	# No kernel tree here by design: --with-config=user builds cmd, lib,
	# man and tests without configuring kernel modules. A staged tree
	# under $SRC is ignored, never required; /usr/src is never used.
	ZSRCBALL="$RECIPE_DIR/files/zfs-2.4.4.tar.gz"
	echo "$zfs_sha256  $ZSRCBALL" | sha256sum -c -
	mkdir -p "$SRC/zfs"
	tar --no-same-owner -C "$SRC/zfs" --strip-components=1 -xf "$ZSRCBALL"
	cd "$SRC/zfs"

	./configure --prefix=/usr --sysconfdir=/etc \
		--localstatedir=/var \
		--with-config=user \
		--enable-systemd=yes \
		--with-systemdunitdir=/usr/lib/systemd/system \
		--with-systemdpresetdir=/usr/lib/systemd/system-preset \
		--with-systemdgeneratordir=/usr/lib/systemd/system-generators \
		--with-systemdmodulesloaddir=/usr/lib/modules-load.d
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
	# Boot-proven unit corrections (Minimer 2026-10-26, CONFIG_ZFS=y and
	# modular alike). Upstream ships these lines and Saphira corrects
	# them here, loudly, because drop-ins cannot fully neutralize them:
	#  1. zfs-import-cache/scan order After systemd-udev-settle, a
	#     deprecated service that stalls 120s and then fails; nothing
	#     in tree pulls it and nothing needs it. Both the Wants= and
	#     the After= lines go (either one alone still stalls).
	#  2. Every unit gates on ConditionPathIsDirectory=/sys/module/zfs,
	#     which is never true on builtin kernels, so no import or mount
	#     unit would ever run there. The gate becomes
	#     ConditionPathExists=/proc/spl/kstat/zfs/arcstats: present from
	#     kernel init on builtin kernels (proven: import completes in
	#     194ms), and present on modular kernels once
	#     modules-load.d/zfs.conf loads the module -- import units
	#     already order After systemd-modules-load.service and mount
	#     orders after import, so one condition serves both.
	# Fail closed on upstream drift: exact expected counts first, zero
	# and full coverage after.
	[ "$(grep -rl '^Wants=systemd-udev-settle\.service$' "$PKGDEST/usr/lib/systemd/system" | wc -l)" -eq 2 ] || {
		echo "ERROR: expected 2 ZFS units wanting udev-settle" >&2
		return 1
	}
	[ "$(grep -rl '^After=systemd-udev-settle\.service$' "$PKGDEST/usr/lib/systemd/system" | wc -l)" -eq 2 ] || {
		echo "ERROR: expected 2 ZFS units after udev-settle" >&2
		return 1
	}
	[ "$(grep -rl '^ConditionPathIsDirectory=/sys/module/zfs$' "$PKGDEST/usr/lib/systemd/system" | wc -l)" -eq 9 ] || {
		echo "ERROR: expected 9 ZFS units gating on /sys/module/zfs" >&2
		return 1
	}
	sed -i '/^Wants=systemd-udev-settle\.service$/d; /^After=systemd-udev-settle\.service$/d' \
		$(grep -rl -e '^Wants=systemd-udev-settle\.service$' -e '^After=systemd-udev-settle\.service$' \
			"$PKGDEST/usr/lib/systemd/system") || return 1
	sed -i 's|^ConditionPathIsDirectory=/sys/module/zfs$|ConditionPathExists=/proc/spl/kstat/zfs/arcstats|' \
		$(grep -rl '^ConditionPathIsDirectory=/sys/module/zfs$' "$PKGDEST/usr/lib/systemd/system") || return 1
	[ -z "$(grep -r 'systemd-udev-settle' "$PKGDEST/usr/lib/systemd/system" || true)" ] || {
		echo "ERROR: udev-settle references remain in ZFS units" >&2
		return 1
	}
	[ -z "$(grep -r 'ConditionPathIsDirectory=/sys/module/zfs' "$PKGDEST/usr/lib/systemd/system" || true)" ] || {
		echo "ERROR: /sys/module/zfs conditions remain in ZFS units" >&2
		return 1
	}
	[ "$(grep -rl '^ConditionPathExists=/proc/spl/kstat/zfs/arcstats$' "$PKGDEST/usr/lib/systemd/system" | wc -l)" -eq 9 ] || {
		echo "ERROR: dual-integration condition missing somewhere" >&2
		return 1
	}
	# Userspace-only proof: a kernel object here means the kernel build
	# leaked back in. Fail closed instead of shipping/colliding with the
	# per-kernel saphira-zfs-<kver> packages.
	if find "$PKGDEST" -name '*.ko' -print -quit 2>/dev/null | grep -q .; then
		echo "ERROR: saphira-zfs-userspace staged kernel modules (expected userspace only)" >&2
		return 1
	fi
	# Upstream's functional test suite (tens of MiB of fixtures like
	# draidcfg.gz) is build-time evidence, never runtime payload: drop
	# it so minimal images do not carry it.
	rm -rf -- "$PKGDEST/usr/share/zfs/zfs-tests"
	# Kernel modules ship in the per-kernel saphira-zfs-<kver> packages,
	# never here: drop whatever this configure's kernel produced so the
	# two outputs can never collide.
	rm -rf -- "$PKGDEST/lib/modules"
	# Dual-init policy: BOTH definitions ship unconditionally; the
	# consumer enables one init's lifecycle, never the recipe. Prove
	# the payload carries both, so a silently single-init package
	# fails the build instead of a systemd (or OpenRC) host at boot.
	for f in zfs-import zfs-load-key zfs-mount zfs-share zfs-zed; do
		[ -f "$PKGDEST/etc/init.d/$f" ] || {
			echo "ERROR: saphira-zfs-userspace payload is missing OpenRC etc/init.d/$f" >&2
			return 1
		}
	done
	for u in zfs-import-cache.service zfs-import-scan.service \
		zfs-import.target zfs-mount.service zfs-mount@.service \
		zfs-share.service zfs-zed.service zfs.target \
		zfs-volume-wait.service zfs-volumes.target \
		zfs-scrub@.service zfs-trim@.service; do
		[ -f "$PKGDEST/usr/lib/systemd/system/$u" ] || {
			echo "ERROR: saphira-zfs-userspace payload is missing systemd unit $u" >&2
			return 1
		}
	done
	# Boot-design helpers, not decoration: the mount generator owns
	# per-dataset key loading, modules-load owns zfs.ko autoload
	# (units gate on arcstats presence, corrected above), the preset
	# owns the upstream enablement policy (inert until
	# `systemctl preset').
	[ -x "$PKGDEST/usr/lib/systemd/system-generators/zfs-mount-generator" ] || {
		echo "ERROR: saphira-zfs-userspace payload is missing the zfs-mount-generator" >&2
		return 1
	}
	[ -f "$PKGDEST/usr/lib/modules-load.d/zfs.conf" ] || {
		echo "ERROR: saphira-zfs-userspace payload is missing modules-load.d/zfs.conf" >&2
		return 1
	}
	[ -f "$PKGDEST/usr/lib/systemd/system-preset/50-zfs.preset" ] || {
		echo "ERROR: saphira-zfs-userspace payload is missing 50-zfs.preset" >&2
		return 1
	}
	# ZFS-root initramfs hook (inert file until composed into an
	# initramfs.conf; see its header for the composition contract).
	install -D -m 0755 "$RECIPE_DIR/files/20-zfs-import" \
		"$PKGDEST/lib/saphira/initramfs/root.d/20-zfs-import"
}
