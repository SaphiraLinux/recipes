#!/bin/sh

pkgname=saphira-zfs-7.3
pkgver=2.4.4
pkgrel=1
# r1: FIRST OpenZFS on Linux 7.3. Upstream 2.4.4 supports kernels up to
# 7.2 (its configure probes fail on the 7.3 inode/bvec/kthread/cpu
# APIs); robn/zfs@linux-7.3-compat carries the fixes against upstream
# master, whose tree has drifted past 2.4.4, so the four changes are
# rebased here rather than vendored blindly:
#   0001 bvec bi_bvec_done -> bi_offset: upstream diff verbatim
#     (79fc679547d6; applies with a benign 1-line offset).
#   0002 kthread fs context (scoped_with_init_fs): upstream e8a0a6cd
#     rebased to 2.4.4 (Makefile.am list, DTRACE-ful taskq_thread).
#   0003 cpu_feature_enabled() over static_cpu_has(): upstream 844c3a4e
#     rebased to 2.4.4 (HAVE_XSAVES guards; _bug probe untouched).
#   0005 iops->create() without flag arg: upstream d01c2c7's autoconf
#     test appended to 2.4.4's existing kernel-inode-create.m4,
#     registered in kernel.m4, zpl_create 3-arg branch in 2.4.4
#     spelling (param keeps the user_ns name so the body is
#     untouched) plus the shadow-guard extension master no longer
#     needs. (Upstream's file-level diff does not fit 2.4.4, so no
#     0004 exists; the mapping is 1:1 with the branch commits.)
# Patching .m4 files means configure is regenerated (autogen.sh)
# rather than shipped. If upstream releases official 7.3 support,
# delete every 000* patch and go back to the plain helper call.
# Tree strategy: the kernel tree is prepared in-worker from vendored
# inputs (kernel tarball + published kernel's own built .config),
# never staged from /usr/src, never mounted in. `buildpkg
# saphira-zfs-7.3` works with no staging step; an explicitly staged
# tree is still honoured after its config is proven. Everything a
# kmod build touches lives under /build.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='OpenZFS 2.4.4 kernel modules for kernel 7.3 (kmods only; userspace is saphira-zfs-userspace)'
license=CDDL
origin=saphira-zfs
repo=saphira
url=https://github.com/openzfs/zfs
source=https://github.com/openzfs/zfs/releases/download/zfs-2.4.4/zfs-2.4.4.tar.gz
sha256=2a3c70d55a37cc71618a95a60e81ad66530201eb118d37741dc92efcf848c8b1

# Per-kernel co-installable output. Install logic lives in
# saphira-kernel/files/kmod-zfs.sh; the build flow below mirrors
# kmod_zfs_build with the 7.3 compat patches applied between extract
# and autogen (the shared helper stays generic -- no per-kernel
# patch mechanism is added to builder infrastructure).
# Kernel identity is the line (KVER_SHORT), not the packaging revision:
# the package name carries the kver, the build tree is the staged
# /usr/src/linux-<kver> tree, and modules land under that KREL's extra/.
# -rN is packaging metadata and stays out of the ABI dependency policy;
# rebuilds follow source/config/KREL changes (release process), and the
# build-time staged-tree config gate enforces exact-tree builds.
depends="kmod saphira-zfs-userspace saphira-kernel-7.3"
# Build secret contract: module signing is mandatory, never optional.
# The worker refuses before spending anything when the builder did
# not expose a readable /keys/module-signing.pem.
saphira_sign_key_required=yes
# saphira-linux-uapi-headers supplies host UAPI (single active line;
# the build tree comes from staged /input). -rN never enters kmod deps.
# autoconf/automake/libtool regenerate configure: the compat patches
# touch config/*.m4, and a shipped configure would silently predate
# them (autogen.sh exists precisely for this; 2.4.4 ships no
# pre-generated configure delta to trust).
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
	autoconf
	automake
	libtool
	make
	pkgconf
	python3
	bc
	bison
	flex
	perl
	pahole
"
# Handover from the retired monolithic saphira-zfs (owned these module
# paths): the file gate exempts retired names listed here, so the split
# successors absorb the paths without collision.
replaces="saphira-zfs"

# Pool compatibility: mounts existing 2.4.1 / 2.4.3 pools; do NOT zpool upgrade.
KVER_SHORT=7.3

recipe_build()
{
	. "$RECIPE_DIR/../saphira-kernel/files/kmod-zfs.sh"
	_kshort=$KVER_SHORT
	_kdir="$SRC/linux-$_kshort"
	_key=/keys/module-signing.pem
	if [ ! -e "$_key" ]; then
		echo "ERROR: module signing key not exposed at $_key (builder key configuration?)" >&2
		return 1
	fi
	if [ ! -r "$_key" ]; then
		echo "ERROR: module signing key exposed but unreadable at $_key (UID ACL missing on the host key? builds must never go unsigned)" >&2
		return 1
	fi
	# Kernel tree: prepared HERE, never staged from /usr/src, never
	# mounted in. Everything a kmod build touches lives under /build:
	# the vendored kernel tarball plus the published kernel's own
	# built .config (saphira-kernel-$_kshort is a depends, so its
	# /boot/config-$_kshort-akadata is in this root). If a tree was
	# explicitly staged (buildpkg <pkg> <inputdir>), it is used only
	# after proving its config; otherwise a fresh tree is prepared.
	# Either way the tree this builds against is exact, and no host
	# state decides it.
	_kconfig="/boot/config-$_kshort-akadata"
	[ -f "$_kdir/Makefile" ] && _staged=1 || _staged=0
	if [ "$_staged" = "1" ]; then
		[ -f "$_kdir/.config" ] ||
			{ echo "ERROR: staged tree has no .config: $_kdir" >&2; return 1; }
		_tree_cfg=$(grep -vE '^[[:space:]]*(#|$)' "$_kdir/.config" | sed -e 's/[[:space:]]*$//' | LC_ALL=C sort)
		_pub_cfg=$(grep -vE '^[[:space:]]*(#|$)' "$_kconfig" | sed -e 's/[[:space:]]*$//' | LC_ALL=C sort)
		[ "$_tree_cfg" = "$_pub_cfg" ] ||
			{ echo "ERROR: staged tree .config disagrees with published $_kconfig (stale tree?)" >&2; return 1; }
	else
		[ -f "$_kconfig" ] ||
			{ echo "ERROR: published kernel config missing at $_kconfig (depends broken?)" >&2; return 1; }
		_kball="$RECIPE_DIR/../saphira-kernel-$_kshort/files/linux-$_kshort.tar.xz"
		[ -f "$_kball" ] || _kball="$RECIPE_DIR/../saphira-kernel-$_kshort/files/linux-$_kshort.tar.gz"
		[ -f "$_kball" ] ||
			{ echo "ERROR: no vendored linux-$_kshort tarball in saphira-kernel-$_kshort/files" >&2; return 1; }
		(cd "$(dirname "$_kball")" && sha256sum -c "$(basename "$_kball").sha256") ||
			{ echo "ERROR: kernel tarball failed its sha256 sidecar" >&2; return 1; }
		rm -rf -- "$_kdir"
		mkdir -p "$_kdir"
		tar --no-same-owner -C "$_kdir" --strip-components=1 -xf "$_kball" ||
			{ echo "ERROR: kernel tarball extraction failed" >&2; return 1; }
		cp "$_kconfig" "$_kdir/.config" ||
			{ echo "ERROR: cannot seed tree .config" >&2; return 1; }
		# Build-time key material, mirroring the kernel recipe:
		# the .config names certs/module-signing.pem and the
		# regdb anchor, and the certs build fails without them.
		# Same bytes, same pins, never stored outside the worker.
		mkdir -p "$_kdir/certs/regdb" ||
			{ echo "ERROR: cannot create tree certs dir" >&2; return 1; }
		cp "$_key" "$_kdir/certs/module-signing.pem" &&
			chmod 600 "$_kdir/certs/module-signing.pem" ||
			{ echo "ERROR: cannot stage module signing key" >&2; return 1; }
		_rdb="$RECIPE_DIR/../wireless-regdb/files/saphira-regdb.x509"
		_rsha="118f8bf6bb8220bb23a8d3cb58359760976b5ba086376cdbc34db9a6d38afc07"
		[ -f "$_rdb" ] ||
			{ echo "ERROR: canonical regdb cert missing at $_rdb" >&2; return 1; }
		echo "$_rsha  $_rdb" | sha256sum -c - ||
			{ echo "ERROR: regdb cert failed its pin" >&2; return 1; }
		cp "$_rdb" "$_kdir/certs/regdb/saphira-regdb.x509" ||
			{ echo "ERROR: cannot stage regdb cert" >&2; return 1; }
		# External-module preparation: a FULL kernel build, not just
		# scripts+prepare. Two proven demands: ZFS configure needs
		# Module.symvers (only modpost generates it), and modpost
		# itself needs vmlinux (without it every core symbol is
		# undefined, proven by mce-inject.ko failing). This is the
		# price of self-staging: ~one full kernel compile per kmod
		# package, all under /build. No modules ship from here;
		# that is the kernel package's job.
		(cd "$_kdir" && make -j${JOBS:-$(nproc)}) ||
			{ echo "ERROR: kernel tree build failed" >&2; return 1; }
	fi
	[ -x "$_kdir/scripts/sign-file" ] ||
		{ echo "ERROR: $_kdir/scripts/sign-file not built" >&2; return 1; }
	_kfull=$(kmod_kver_full "$_kdir") ||
		{ echo "ERROR: cannot derive kernel release from $_kdir/Makefile" >&2; return 1; }

	_zball=$(kmod_srcball "$RECIPE_DIR/files/zfs-2.4.4.tar.gz" "$sha256") || return 1
	_zdir="$SRC/zfs-$_kfull"
	rm -rf -- "$_zdir"
	mkdir -p "$_zdir"
	tar --no-same-owner -C "$_zdir" --strip-components=1 -xf "$_zball"
	cd "$_zdir"

	# Linux 7.3 compat, applied in order, fail-closed: an unexpected
	# context (upstream drift) fails the build rather than shipping
	# half-patched sources. --forward so re-runs are safe; patches
	# are exact (no fuzz tolerated: any fuzz line below fails).
	for patch in "$RECIPE_DIR"/files/000*.patch; do
		patch -p1 --forward < "$patch" > "$_zdir/patch.log" 2>&1 || {
			echo "ERROR: 7.3 compat patch failed: ${patch##*/}" >&2
			tail -5 "$_zdir/patch.log" >&2
			return 1
		}
		if grep -qE 'fuzz|offset' "$_zdir/patch.log"; then
			echo "ERROR: ${patch##*/} applied loosely (fuzz/offset): rebase it, do not ship drift" >&2
			grep -E 'fuzz|offset' "$_zdir/patch.log" >&2
			return 1
		fi
	done

	./autogen.sh || return 1
	# --enable-linux-experimental: upstream's designed escape hatch
	# for kernels past ZFS_META_KVER_MAX (7.2). It changes no code
	# paths (only an EXPERIMENTAL dmesg warning, which is honest
	# for a first-to-7.3 attempt); the allowlist itself stays
	# untouched so a future official 7.3 release drops this flag
	# instead of carrying a version lie. Remove together with the
	# 000* patches when that lands.
	./configure --prefix=/usr --sysconfdir=/etc \
		--with-linux="$_kdir" --with-linux-obj="$_kdir" \
		--with-config=all --enable-linux-experimental || return 1
	make -j${JOBS:-$(nproc)} || return 1

	for ko in module/*.ko; do
		"$_kdir/scripts/sign-file" sha256 "$_key" "$_key" "$ko" || return 1
	done
}

recipe_install()
{
	. "$RECIPE_DIR/../saphira-kernel/files/kmod-zfs.sh"
	kmod_zfs_install "$KVER_SHORT"
}
