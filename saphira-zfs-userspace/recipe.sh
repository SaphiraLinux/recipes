#!/bin/sh

pkgname=saphira-zfs-userspace
pkgver=2.4.4
pkgrel=2
# r2: enable upstream systemd integration (Minimer proof: r1 installed
# the OpenRC scripts but no systemd units, so a systemd host had no
# ZFS import/mount/ZED boot lifecycle). Root cause: upstream
# --enable-systemd defaults to `check', which probes `systemctl
# --version' on the BUILD host; the worker root has no systemctl, so
# units, generator, preset and modules-load.d were silently skipped.
# The recipe now passes --enable-systemd=yes with explicit Saphira
# paths (never host-probed), and ships the upstream unit set
# verbatim: import-cache/scan + import.target (complementary cache
# conditions, no duplicate import), mount (+@ template), share,
# zed, zfs.target, volume-wait + volumes.target, scrub/trim services
# + timers (inert unless enabled), 50-zfs.preset (inert until
# `systemctl preset' runs - install enables nothing), the
# zfs-mount-generator (per-dataset zfs-load-key@ units; 2.4.4 has no
# static zfs-load-key.service - the generator IS the key machinery),
# and modules-load.d/zfs.conf (without it every unit's
# ConditionPathIsDirectory=/sys/module/zfs skips silently).
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
	saphira-kernel-headers
	make
	pkgconf
	python3
"
# Handover from the retired monolithic saphira-zfs (owned userspace,
# man pages and docs): the file gate exempts retired names listed here.
replaces="saphira-zfs"

# Needs a configured kernel tree for --with-linux, so this also takes
# the /input staging directory (any staged tree will do; userspace is
# kernel-independent). Assemble with:
#   /recipes//recipes/saphira-kernel/files/stage-kmod-input.sh /build/kernel-input
#   buildpkg saphira-zfs-userspace /build/kernel-input
# Pool compatibility: mounts existing 2.4.1 / 2.4.3 pools; do NOT zpool upgrade.

recipe_build()
{
	export TAR_OPTIONS=--no-same-owner
	# Newest staged tree configures the build; the output does not depend
	# on which one (fail closed when none is staged).
	KDIR=$(for d in "$SRC"/linux-*/; do [ -d "$d" ] && printf '%s\n' "$d"; done | sort -V | tail -1)
	[ -n "$KDIR" ] && [ -f "$KDIR/Makefile" ] || { echo "ERROR: no staged kernel tree under $SRC (staged /input?)" >&2; return 1; }

	ZSRCBALL="$RECIPE_DIR/files/zfs-2.4.4.tar.gz"
	echo "$zfs_sha256  $ZSRCBALL" | sha256sum -c -
	mkdir -p "$SRC/zfs"
	tar --no-same-owner -C "$SRC/zfs" --strip-components=1 -xf "$ZSRCBALL"
	cd "$SRC/zfs"

	./configure --prefix=/usr --sysconfdir=/etc \
		--localstatedir=/var \
		--with-linux="$KDIR" --with-linux-obj="$KDIR" \
		--with-config=all \
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
	# (every unit gates on /sys/module/zfs), the preset owns the
	# upstream enablement policy (inert until `systemctl preset').
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
}
