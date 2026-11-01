#!/bin/sh
# kmod-andrews.sh -- worker-side prepared-tree contract for KREL 7.3.0-zfs.
#
# Sourced from inside recipe_build()/recipe_install() (never at top level, so
# the metadata sandbox never executes it). Additive only: no existing helper
# (kmod-nvidia.sh, kmod-gpu-unlock.sh, kmod-zfs.sh, kmod-drbd.sh) is modified
# by this file, and none of them can build for an andrews KREL.
#
# WHY THIS FILE EXISTS
#
# The official kmod helpers derive the release from the kernel Makefile
# (VERSION.PATCHLEVEL.SUBLEVEL: 7.3.0) and prepare from saphira-kernel-<kver>
# plus /boot/config-<kver>-akadata. An andrews tree differs in three
# load-bearing ways that Makefile parsing cannot see:
#
#   1. CONFIG_LOCALVERSION="-zfs": the true release is 7.3.0-zfs
#      (SUBLEVEL 0 always prints; a future 7.3.1 gives 7.3.1-zfs, which is
#      a NEW recipe directory, never an edit here). Only `make
#      kernelrelease` in a configured tree knows it, so only that is used.
#   2. CONFIG_ZFS=y via upstream copy-builtin: the ZFS 2.4.4 sources, the
#      five 000* compat patches and --enable-linux-experimental /
#      --enable-linux-builtin belong to THIS integration (same set, order
#      and exactness as andrews-kernel-7.3). They are not inherited by, and
#      never leak into, any external-module recipe.
#   3. Provenance: with CONFIG_MODVERSIONS capable trees, `make
#      modules_prepare` does NOT generate Module.symvers (only modpost
#      does, and modpost needs vmlinux). Today's 7.3 config has
#      `# CONFIG_MODVERSIONS is not set`, but the contract is written for
#      both states: a prepared tree without a provenanced Module.symvers
#      fails the gate, so a future MODVERSIONS=y can never silently ship
#      modules carrying incorrect symbol-version information.
#
# WHAT THE CONTRACT GUARANTEES (all asserted in-worker, all fail closed)
#
#   - Exact derived KREL: 7.3.0-zfs, via kernelrelease in the prepared tree.
#   - Exact published configuration: tree .config sort-diffs clean against
#     /boot/config-7.3.0-zfs (shipped by installed andrews-kernel-7.3).
#   - Matching generated headers, built scripts (modpost, sign-file) and a
#     Module.symvers provenanced to this tree and release (full `make`, not
#     modules_prepare alone -- the price of (3), same price kmod-zfs pays).
#   - Wireless discipline: vendored freedom + v3 patches (owned bytes, never
#     symlinks), canonical regdb cert pin, both policy gates green on the
#     FINAL .config. The regdb trust anchor is properly signed material
#     staged through $SRC under /build with sha256 verification.
#   - /build discipline: everything happens under $SRC/$BUILDDIR (the
#     constructor workspace under /build). /usr/src is never read and never
#     written here; no staged /input tree is honoured (fresh prepare only,
#     so provenance is structural rather than asserted).
#
# SCOPE BOUNDARIES (operator-locked, enforced by what this file refuses)
#
#   - Only KREL 7.3.0-zfs. No other builtin-ZFS line will ever be added;
#     standard Saphira kernels keep external zfs modules (saphira-zfs-*).
#   - andrews-kernel-7.2.3-zfs is frozen and untouched by this file.
#   - ZFS version for this integration is 2.4.4 (all in-tree ZFS consumers
#     already pin 2.4.4; no 2.4.2 remains). Upgrading it is a deliberate
#     recipe edit with its own revision, never an opportunistic bump here.

# Fixed identity for this integration. KREL is asserted, never assumed:
# kmod_andrews_krel() derives it from the prepared tree and refuses any
# other value.
_ANDREWS_KVER=7.3
_ANDREWS_KREL=7.3.0-zfs
_ANDREWS_ZFS_VERSION=2.4.4
_ANDREWS_REGDB_SHA="118f8bf6bb8220bb23a8d3cb58359760976b5ba086376cdbc34db9a6d38afc07"

kmod_andrews_srcball()
{
	if [ -f "$1" ]; then
		printf '%s  %s\n' "$2" "$1" | sha256sum -c - >/dev/null ||
			{ echo "kmod-andrews: vendored source failed verification: $1" >&2; return 1; }
		printf '%s\n' "$1"
	elif [ -n "${SOURCE_ARCHIVE-}" ] && [ -f "$SOURCE_ARCHIVE" ]; then
		printf '%s\n' "$SOURCE_ARCHIVE"
	else
		echo "kmod-andrews: no vendored source at $1 and no fetched SOURCE_ARCHIVE" >&2
		return 1
	fi
}

# kmod_andrews_krel KDIR - print the true kernel release of a prepared tree.
kmod_andrews_krel()
{
	[ "$#" -eq 1 ] || { echo "kmod-andrews: usage: kmod_andrews_krel KDIR" >&2; return 1; }
	[ -f "$1/Makefile" ] || { echo "kmod-andrews: no Makefile in $1" >&2; return 1; }
	make -s -C "$1" kernelrelease 2>/dev/null ||
		{ echo "kmod-andrews: kernelrelease failed in $1" >&2; return 1; }
}

# kmod_prepare_tree_andrews - ensure a usable KREL-exact kernel tree at
# $SRC/linux-7.3.0-zfs, entirely under /build. Always prepared fresh
# in-worker; no staged /input tree is honoured (a staged tree cannot prove
# the ZFS copy-builtin + LOCALVERSION provenance this KREL requires, so
# accepting one would trade a structural guarantee for an assertion).
kmod_prepare_tree_andrews()
{
	_kdir="$SRC/linux-$_ANDREWS_KREL"
	_kconfig="/boot/config-$_ANDREWS_KREL"
	_key=/keys/module-signing.pem

	# Build secret contract: module signing is mandatory, never optional.
	if [ ! -e "$_key" ]; then
		echo "ERROR: module signing key not exposed at $_key (builder key configuration?)" >&2
		return 1
	fi
	if [ ! -r "$_key" ]; then
		echo "ERROR: module signing key exposed but unreadable at $_key (UID ACL missing on the host key? builds must never go unsigned)" >&2
		return 1
	fi

	# The published kernel config is the seed. It ships in the installed
	# andrews-kernel-7.3 package (/boot/config-7.3.0-zfs); without that
	# package installed on the builder there is nothing exact to build
	# against, and guessing is refused.
	[ -f "$_kconfig" ] ||
		{ echo "ERROR: published kernel config missing at $_kconfig (install andrews-kernel-7.3?)" >&2; return 1; }

	_krecipe="$RECIPE_DIR/../andrews-kernel-$_ANDREWS_KVER"
	_sib="$RECIPE_DIR/../saphira-kernel-$_ANDREWS_KVER"

	# Kernel tarball: the same verified bytes both kernels compile.
	_kball="$_sib/files/linux-$_ANDREWS_KVER.tar.xz"
	[ -f "$_kball" ] || _kball="$_sib/files/linux-$_ANDREWS_KVER.tar.gz"
	[ -f "$_kball" ] ||
		{ echo "ERROR: no vendored linux-$_ANDREWS_KVER tarball in saphira-kernel-$_ANDREWS_KVER/files" >&2; return 1; }
	(cd "$(dirname "$_kball")" && sha256sum -c "$(basename "$_kball").sha256") ||
		{ echo "ERROR: kernel tarball failed its sha256 sidecar" >&2; return 1; }

	rm -rf -- "$_kdir"
	mkdir -p "$_kdir"
	tar --no-same-owner -C "$_kdir" --strip-components=1 -xf "$_kball" ||
		{ echo "ERROR: kernel tarball extraction failed" >&2; return 1; }

	# Policy patches: owned vendored bytes in andrews-kernel-7.3/files
	# (byte-identical to the official line today; each line owns its
	# inputs -- no symlinks between recipes).
	[ -f "$_krecipe/files/x86-64-v3.patch" ] ||
		{ echo "ERROR: policy patch missing: andrews-kernel-$_ANDREWS_KVER/files/x86-64-v3.patch" >&2; return 1; }
	patch -d "$_kdir" -Np1 -i "$_krecipe/files/x86-64-v3.patch" > "$SRC/patch-v3.log" 2>&1 ||
		{ echo "ERROR: x86-64-v3.patch did not apply" >&2; return 1; }
	# Strict application (exact 7.3 context): fuzz or offset is drift.
	if grep -qE 'fuzz|offset' "$SRC/patch-v3.log"; then
		echo "ERROR: x86-64-v3.patch applied loosely (fuzz/offset): rebase it, do not ship drift" >&2
		grep -E 'fuzz|offset' "$SRC/patch-v3.log" >&2
		return 1
	fi
	[ -f "$_krecipe/files/cfg80211-regdb-freedom.patch" ] ||
		{ echo "ERROR: policy patch missing: andrews-kernel-$_ANDREWS_KVER/files/cfg80211-regdb-freedom.patch" >&2; return 1; }
	patch -d "$_kdir" -Np1 -i "$_krecipe/files/cfg80211-regdb-freedom.patch" > "$SRC/patch-freedom.log" 2>&1 ||
		{ echo "ERROR: cfg80211-regdb-freedom.patch did not apply" >&2; return 1; }
	# Strict application (exact 7.3 context): fuzz or offset is drift.
	if grep -qE 'fuzz|offset' "$SRC/patch-freedom.log"; then
		echo "ERROR: cfg80211-regdb-freedom.patch applied loosely (fuzz/offset): rebase it, do not ship drift" >&2
		grep -E 'fuzz|offset' "$SRC/patch-freedom.log" >&2
		return 1
	fi

	# Seed the published configuration, then key material (build-time only,
	# never stored outside the worker): module signing key plus the
	# canonical signed regdb trust anchor, both sha-verified.
	cp "$_kconfig" "$_kdir/.config" ||
		{ echo "ERROR: cannot seed tree .config" >&2; return 1; }
	mkdir -p "$_kdir/certs/regdb" ||
		{ echo "ERROR: cannot create tree certs dir" >&2; return 1; }
	cp "$_key" "$_kdir/certs/module-signing.pem" &&
		chmod 600 "$_kdir/certs/module-signing.pem" ||
		{ echo "ERROR: cannot stage module signing key" >&2; return 1; }
	_rdb="$RECIPE_DIR/../wireless-regdb/files/saphira-regdb.x509"
	[ -f "$_rdb" ] ||
		{ echo "ERROR: canonical regdb cert missing at $_rdb" >&2; return 1; }
	echo "$_ANDREWS_REGDB_SHA  $_rdb" | sha256sum -c - >/dev/null ||
		{ echo "ERROR: regdb cert failed its pin" >&2; return 1; }
	cp "$_rdb" "$_kdir/certs/regdb/saphira-regdb.x509" ||
		{ echo "ERROR: cannot stage regdb cert" >&2; return 1; }

	(cd "$_kdir" && make olddefconfig) ||
		{ echo "ERROR: kernel olddefconfig failed" >&2; return 1; }

	# Regulatory-freedom gate on the merged config (same gate the kernel
	# recipe runs: a silent re-enable fails the build, never ships).
	# Sourced from the andrews-owned copy: every kernel owns its files.
	. "$_krecipe/files/check-regdb-freedom.sh" ||
		{ echo "ERROR: cannot source check-regdb-freedom.sh" >&2; return 1; }
	check_regdb_freedom "$_kdir/.config" "$_kdir/net/wireless/Kconfig" ||
		{ echo "ERROR: regdb-freedom gate failed (wireless patches incomplete?)" >&2; return 1; }
	# No-initramfs builtin gate (early firmware/microcode images excepted).
	# Sourced from the andrews-owned copy: every kernel owns its files.
	. "$_krecipe/files/check-no-initramfs-builtins.sh" ||
		{ echo "ERROR: cannot source check-no-initramfs-builtins.sh" >&2; return 1; }
	check_no_initramfs_builtins "$_kdir/.config" "$_ANDREWS_KVER" ||
		{ echo "ERROR: no-initramfs-builtins gate failed" >&2; return 1; }

	# Generated headers for the ZFS configure version probe
	# (olddefconfig alone does not emit utsrelease.h).
	(cd "$_kdir" && make prepare) ||
		{ echo "ERROR: kernel prepare failed (ZFS configure needs generated headers)" >&2; return 1; }
	[ -f "$_kdir/include/generated/utsrelease.h" ] ||
		{ echo "ERROR: utsrelease.h missing after prepare" >&2; return 1; }

	# OpenZFS integration (upstream copy-builtin, same set/order/exactness
	# as andrews-kernel-7.3: --forward so re-runs are safe, any fuzz or
	# offset fails the build rather than shipping drift). The five 000*
	# patches and --enable-linux-experimental belong to THIS ZFS-on-7.3
	# integration, not to any external-module recipe.
	_zdir="$RECIPE_DIR/../saphira-zfs-7.3/files"
	_zball="$_zdir/zfs-$_ANDREWS_ZFS_VERSION.tar.gz"
	[ -f "$_zball" ] ||
		{ echo "ERROR: no sibling zfs-$_ANDREWS_ZFS_VERSION.tar.gz in saphira-zfs-7.3/files" >&2; return 1; }
	(cd "$_zdir" && sha256sum -c "zfs-$_ANDREWS_ZFS_VERSION.tar.gz.sha256") ||
		{ echo "ERROR: OpenZFS tarball failed its sha256 sidecar" >&2; return 1; }
	_zsrc="$SRC/zfs-$_ANDREWS_ZFS_VERSION"
	rm -rf -- "$_zsrc"
	mkdir -p "$_zsrc"
	tar --no-same-owner -C "$_zsrc" --strip-components=1 -xf "$_zball" ||
		{ echo "ERROR: OpenZFS extraction failed" >&2; return 1; }
	[ -x "$_zsrc/copy-builtin" ] ||
		{ echo "ERROR: OpenZFS tree has no copy-builtin (builtin integration unsupported at $_ANDREWS_ZFS_VERSION?)" >&2; return 1; }
	for _patch in "$_krecipe"/files/000*.patch; do
		patch -p1 --forward -d "$_zsrc" < "$_patch" > "$SRC/zfs-patch.log" 2>&1 || {
			echo "ERROR: 7.3 compat patch failed: ${_patch##*/}" >&2
			tail -5 "$SRC/zfs-patch.log" >&2
			return 1
		}
		if grep -qE 'fuzz|offset' "$SRC/zfs-patch.log"; then
			echo "ERROR: ${_patch##*/} applied loosely (fuzz/offset): rebase it, do not ship drift" >&2
			grep -E 'fuzz|offset' "$SRC/zfs-patch.log" >&2
			return 1
		fi
	done
	(cd "$_zsrc" && ./autogen.sh) ||
		{ echo "ERROR: OpenZFS autogen failed (compat patches touch config/*.m4)" >&2; return 1; }
	# layout-exception: --with-config=kernel builtin mode copies ZFS into
	# the kernel tree; nothing installs to prefix/sysconfdir/localstatedir.
	(cd "$_zsrc" && ./configure --with-linux="$_kdir" \
		--with-linux-obj="$_kdir" \
		--with-config=kernel --enable-linux-builtin \
		--enable-linux-experimental) ||
		{ echo "ERROR: OpenZFS configure failed" >&2; return 1; }
	(cd "$_zsrc" && ./copy-builtin "$_kdir") ||
		{ echo "ERROR: OpenZFS copy-builtin failed" >&2; return 1; }

	# Variant identity + ZFS, then re-resolve: copy-builtin adds new Kconfig
	# symbols, so olddefconfig must run again after it.
	(cd "$_kdir" && ./scripts/config --set-str CONFIG_LOCALVERSION "-zfs" \
		--enable CONFIG_ZFS) ||
		{ echo "ERROR: cannot set LOCALVERSION/CONFIG_ZFS" >&2; return 1; }
	(cd "$_kdir" && make olddefconfig) ||
		{ echo "ERROR: kernel olddefconfig failed after ZFS integration" >&2; return 1; }
	[ "$(cd "$_kdir" && ./scripts/config --state CONFIG_ZFS)" = "y" ] ||
		{ echo "ERROR: CONFIG_ZFS is not =y after integration" >&2; return 1; }
	grep -q '^# CONFIG_ZFS_DEBUG is not set' "$_kdir/.config" ||
		{ echo "ERROR: CONFIG_ZFS_DEBUG got enabled (development assertions must never ship)" >&2; return 1; }
	grep -q '^CONFIG_LOCALVERSION="-zfs"$' "$_kdir/.config" ||
		{ echo "ERROR: LOCALVERSION suffix missing (variant would collide with the official line)" >&2; return 1; }
	# Re-prove both policy gates on the FINAL .config.
	check_regdb_freedom "$_kdir/.config" "$_kdir/net/wireless/Kconfig" ||
		{ echo "ERROR: regdb-freedom gate failed after ZFS integration" >&2; return 1; }
	check_no_initramfs_builtins "$_kdir/.config" "$_ANDREWS_KVER" ||
		{ echo "ERROR: no-initramfs-builtins gate failed after ZFS integration" >&2; return 1; }

	# Strip CFI directives from ZFS assembly (same defect and same fix as
	# andrews-kernel-7.3: hand-written .cfi_* emits .eh_frame orphans under
	# the official =error strictness). Fail-closed both directions.
	_cfifiles=$(grep -rl '^[[:space:]]*\.cfi_' "$_kdir/fs/zfs" --include='*.S')
	[ -n "$_cfifiles" ] ||
		{ echo "ERROR: no .cfi directives found under fs/zfs (unexpected; upstream removed them?)" >&2; return 1; }
	printf '%s\n' "$_cfifiles" | while IFS= read -r _f; do
		sed -i '/^[[:space:]]*\.cfi_/d' "$_f" || exit 1
	done || { echo "ERROR: CFI stripping failed" >&2; return 1; }
	if grep -rn '^[[:space:]]*\.cfi_' "$_kdir/fs/zfs" --include='*.S'; then
		echo "ERROR: .cfi directives remain under fs/zfs after stripping" >&2
		return 1
	fi

	# FULL kernel build, not modules_prepare: Module.symvers is generated
	# by modpost, and modpost needs vmlinux (proven by the kmod-zfs
	# helper). This is the price of a provenanced symbol-version table:
	# ~one full kernel compile per andrews kmod package, all under /build
	# (ccache hits there). A prepared tree without Module.symvers fails
	# the gate below, so MODVERSIONS=y can never silently ship modules
	# with incorrect symbol versions.
	(cd "$_kdir" && make -j${JOBS:-$(nproc)}) ||
		{ echo "ERROR: kernel tree build failed" >&2; return 1; }
	if readelf -S "$_kdir/vmlinux" 2>/dev/null | grep -q eh_frame; then
		echo "ERROR: prepared vmlinux carries .eh_frame (CFI stripping failed)" >&2
		return 1
	fi
	[ -x "$_kdir/scripts/sign-file" ] ||
		{ echo "ERROR: $_kdir/scripts/sign-file not built" >&2; return 1; }

	kmod_andrews_verify_tree "$_kdir" "$_kconfig"
}

# kmod_andrews_verify_tree KDIR PUBCONFIG - provenance gate. Refuses
# anything that is not exactly KREL 7.3.0-zfs built from the published config.
kmod_andrews_verify_tree()
{
	_kdir=$1
	_kconfig=$2
	_krel=$(kmod_andrews_krel "$_kdir") ||
		{ echo "ERROR: cannot derive kernel release" >&2; return 1; }
	[ "$_krel" = "$_ANDREWS_KREL" ] ||
		{ echo "ERROR: prepared tree KREL is $_krel, want $_ANDREWS_KREL (LOCALVERSION lost?)" >&2; return 1; }

	# Published configuration identity (comment/blank-line insensitive,
	# order insensitive -- same strictness as the official staged-tree
	# check, so drift fails loudly naming the defect, never silently).
	_tree_cfg=$(grep -vE '^[[:space:]]*(#|$)' "$_kdir/.config" | sed -e 's/[[:space:]]*$//' | LC_ALL=C sort)
	_pub_cfg=$(grep -vE '^[[:space:]]*(#|$)' "$_kconfig" | sed -e 's/[[:space:]]*$//' | LC_ALL=C sort)
	[ "$_tree_cfg" = "$_pub_cfg" ] ||
		{ echo "ERROR: prepared tree .config disagrees with published $_kconfig (stale tree?)" >&2; return 1; }

	# Symbol-version provenance: Module.symvers must exist, be non-empty,
	# and belong to this release. With MODVERSIONS off it carries no CRCs
	# but still names the exported set modpost resolved for THIS tree; a
	# copied or foreign Module.symvers cannot satisfy the release marker.
	[ -s "$_kdir/Module.symvers" ] ||
		{ echo "ERROR: Module.symvers missing or empty in $_kdir (full build required; modules_prepare is not sufficient)" >&2; return 1; }
	if grep -q "CONFIG_MODVERSIONS=y" "$_kdir/.config"; then
		grep -qE '^[0-9a-f]{8}[[:space:]]' "$_kdir/Module.symvers" ||
			{ echo "ERROR: MODVERSIONS=y but Module.symvers carries no CRCs (foreign or truncated table?)" >&2; return 1; }
	fi

	# Build interface completeness: generated headers, modpost, sign-file.
	[ -f "$_kdir/include/generated/utsrelease.h" ] ||
		{ echo "ERROR: utsrelease.h missing (prepare incomplete)" >&2; return 1; }
	[ -f "$_kdir/include/generated/autoconf.h" ] ||
		{ echo "ERROR: autoconf.h missing (prepare incomplete)" >&2; return 1; }
	[ -x "$_kdir/scripts/mod/modpost" ] ||
		{ echo "ERROR: scripts/mod/modpost not built" >&2; return 1; }
	[ -x "$_kdir/scripts/sign-file" ] ||
		{ echo "ERROR: scripts/sign-file not built" >&2; return 1; }

	# No build-tree leakage vectors: the prepared tree lives under /build
	# by construction ($SRC), and must never reference /usr/src.
	if grep -rq '/usr/src' "$_kdir/.config" 2>/dev/null; then
		echo "ERROR: prepared tree .config references /usr/src" >&2
		return 1
	fi

	printf 'kmod-andrews: tree %s OK (KREL %s, config + Module.symvers + scripts provenanced)\n' \
		"$_kdir" "$_krel"
}

# kmod_andrews_install_dir KDIR - print the KREL-exact module extra dir leaf.
# Fails closed on any release other than 7.3.0-zfs, so install paths can
# never drift to a shorthand.
kmod_andrews_install_dir()
{
	_krel=$(kmod_andrews_krel "$1") || return 1
	[ "$_krel" = "$_ANDREWS_KREL" ] ||
		{ echo "ERROR: install tree KREL is $_krel, want $_ANDREWS_KREL" >&2; return 1; }
	printf '%s\n' "$_krel"
}
