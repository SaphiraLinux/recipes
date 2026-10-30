#!/bin/sh

pkgname=andrews-kernel-7.3
# Andrew's personal experimental Linux kernel, entirely independent of
# AKADATA branding and Saphira's official kernel releases. Saphira
# provides the build infrastructure (builder, gates, hooks); it does
# not own this kernel's identity. 7.3 line: matches the Minimer test
# target instead of downgrading to 7.2.3.
#
# Objective: native ZFS root boot — no initramfs, no early userspace —
# with OpenZFS compiled INTO vmlinux (CONFIG_ZFS=y) via upstream
# copy-builtin. Milestone (a) only: the driver is present at boot;
# pool import and root-dataset mounting without initramfs is a
# separate milestone and is NOT provided by this revision.
#
# Co-installable with saphira-kernel-7.3: CONFIG_LOCALVERSION="-zfs"
# gives KREL 7.3-zfs, so /boot names and /lib/modules never collide
# with the official line. External kmod packages built for KREL 7.3
# refuse to load here by vermagic (correct direction: fail closed,
# never silently). Within this package, revisions supersede normally.
#
# kernel_version is FIXED (no override): tarball, config, patches and
# the sibling recipe paths below all follow it.
#
# Identity rule: no AKADATA naming, no release suffixes. /boot
# artefacts are vmlinuz-7.3-zfs, System.map-7.3-zfs and config-7.3-zfs
# — the shared -akadata boot-name gate cannot assert these (it
# mandates the suffix by design and must not be weakened), so this
# recipe carries its own exact-name assertion instead.
#
# Distribution posture (deliberate, read before publishing): this
# recipe is the distributable artefact. It combines pinned GPLv2
# kernel sources with pinned CDDL OpenZFS sources at BUILD time,
# inside the isolated worker. The payload therefore contains CDDL
# objects linked into vmlinux (see README in the package). Whether
# the built binary is published is an operator release decision
# (signing is manual and operator-only); nothing here pre-approves it.
# No prebuilt combined kernel ships merely because this recipe exists.
kernel_version=7.3
pkgver=1
pkgrel=1
# r1: first andrews-kernel 7.3 revision. Mirrors saphira-kernel-7.3
# (config, patches, gates, hooks, size policy) plus OpenZFS 2.4.4
# integrated via copy-builtin with CONFIG_ZFS=y. 7.3 needs the five
# numbered compat patches (0001/0002/0003/0005/0006, same set and
# same exactness rules as saphira-zfs-7.3: --forward, no fuzz/offset)
# applied between extract and autogen, plus --enable-linux-experimental
# (upstream's designed escape hatch past ZFS_META_KVER_MAX; changes no
# code paths, only an honest EXPERIMENTAL dmesg warning). Patches are
# vendored in files/ (see PATCHES.md), owned by this recipe. Kernel
# tarball/config/gates/hooks and the OpenZFS tarball stay referenced
# from the sibling trees (pinned, sidecar-verified); every input is
# sha256-verified at build time.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Andrew's kernel 7.3 with OpenZFS built in (CONFIG_ZFS=y, KREL 7.3-zfs, experimental)"
license=GPL-2.0-only
origin="$pkgname"
repo=saphira
url=https://saphira.vm2.uk/

# NOTE on license=: matches the kernel line this build mirrors. The
# payload additionally contains CDDL-licensed OpenZFS objects compiled
# into vmlinux; that fact is carried IN the payload (README) rather
# than hidden, and publication remains an explicit operator decision
# (see header above).

# Sibling inputs (all pinned, all verified at build time):
# - kernel tarball + .sha256 sidecar: ../saphira-kernel-7.3/files/
# - kernel config, patches, gates, hooks: same directory
# - OpenZFS tarball + .sha256 sidecar + 000* compat patches:
#   ../saphira-zfs-7.3/files/
# - regdb anchor: ../wireless-regdb/files/saphira-regdb.x509 (pinned)
zfs_version=2.4.4

# Build secret contract: module signing is mandatory, never optional.
# The worker refuses before spending anything when the builder did
# not expose a readable /keys/module-signing.pem.
saphira_sign_key_required=yes
makedepends="
	bc
	binutils
	kmod
	elfutils-dev
	bison
	m4
	flex
	gawk
	gcc
	openssl-dev
	make
	perl
	pahole
	zlib-dev
	autoconf
	automake
	libtool
"
# makedepends mirrors the 7.3 official line, plus autoconf/automake/
# libtool: the 000* compat patches touch config/*.m4, so configure must
# be regenerated (autogen.sh) rather than trusting the shipped one. If
# upstream releases official 7.3 support, the patches, autogen and
# --enable-linux-experimental go away together.

# Variant release suffix: keeps this package co-installable with the
# official 7.3 kernel (distinct KREL, vermagic, /boot names, module
# dir). The suffix is a technical discriminator, not a release brand.
zfs_localversion="-zfs"

recipe_build()
{
	# Module signing key: exposed by the builder read-only at the fixed
	# in-namespace path /keys/module-signing.pem (canonical host key
	# /etc/saphira/keys/module-signing.pem, never in /recipes, never
	# staged through /build). Absent key fails closed below.
	KEY=/keys/module-signing.pem
	if [ ! -e "$KEY" ]; then
		echo "ERROR: module signing key not exposed at $KEY (builder key configuration?)" >&2
		return 1
	fi
	if [ ! -r "$KEY" ]; then
		echo "ERROR: module signing key exposed but unreadable at $KEY (UID ACL missing on the host key? builds must never go unsigned)" >&2
		return 1
	fi
	export TAR_OPTIONS=--no-same-owner
	SIB="$RECIPE_DIR/../saphira-kernel-${kernel_version}/files"

	# Kernel sources: sibling-vendored, sidecar-verified (same pin as
	# the official line; never re-downloaded, never trusted by path).
	KBALL="$SIB/linux-${kernel_version}.tar.xz"
	[ -f "$KBALL" ] || KBALL="$SIB/linux-${kernel_version}.tar.gz"
	[ -f "$KBALL" ] ||
		{ echo "ERROR: no sibling linux-${kernel_version}.tar.{xz,gz} in $SIB" >&2; return 1; }
	(cd "$SIB" && sha256sum -c "$(basename "$KBALL").sha256") ||
		{ echo "ERROR: kernel tarball failed its sha256 sidecar" >&2; return 1; }
	mkdir -p "$SRC/linux-${kernel_version}"
	tar --no-same-owner -C "$SRC/linux-${kernel_version}" --strip-components=1 -xf "$KBALL"
	cd "$SRC/linux-${kernel_version}"

	patch -Np1 -i "$RECIPE_DIR/files/x86-64-v3.patch"
	# Regulatory freedom (article: kernel must not mandate regdb
	# signatures): flip the two gatekeeper Kconfig defaults y -> n so
	# an absent symbol can never resolve to enforced verification.
	# Fails closed on upstream drift like the v3 patch. The recipe
	# config carries both symbols as explicit "is not set"; the gate
	# below proves the final .config after olddefconfig.
	# Both patches are vendored in files/ (see PATCHES.md), not
	# referenced from the sibling line: this recipe owns its inputs.
	patch -Np1 -i "$RECIPE_DIR/files/cfg80211-regdb-freedom.patch"
	cp "$SIB/config-${kernel_version}-akadata" "$SRC/linux-${kernel_version}/.config"
	mkdir -p "$SRC/linux-${kernel_version}/certs/regdb"
	# Canonical regdb trust anchor: single copy in wireless-regdb/files/,
	# staged through $SRC (under /build) with sha256 verification.
	# Preserved bytes (sha256 118f8bf6bb8220bb23a8d3cb58359760976b5ba086376cdbc34db9a6d38afc07);
	# regenerating would break regulatory.db verification. Legacy
	# per-recipe files/ copies are removed; do not re-vendor.
	REGDB_CANONICAL="$RECIPE_DIR/../wireless-regdb/files/saphira-regdb.x509"
	REGDB_SHA="118f8bf6bb8220bb23a8d3cb58359760976b5ba086376cdbc34db9a6d38afc07"
	[ -f "$REGDB_CANONICAL" ] || { echo "ERROR: canonical regdb cert missing at $REGDB_CANONICAL" >&2; return 1; }
	echo "$REGDB_SHA  $REGDB_CANONICAL" | sha256sum -c - || return 1
	STAGED_REGDB="$SRC/saphira-regdb.x509"
	cp "$REGDB_CANONICAL" "$STAGED_REGDB"
	echo "$REGDB_SHA  $STAGED_REGDB" | sha256sum -c - || return 1
	cp "$STAGED_REGDB" "$SRC/linux-${kernel_version}/certs/regdb/saphira-regdb.x509"
	cp "$KEY" "$SRC/linux-${kernel_version}/certs/module-signing.pem"
	chmod 600 "$SRC/linux-${kernel_version}/certs/module-signing.pem"

	make olddefconfig
	# Regulatory-freedom gate: prove BOTH gatekeepers are disabled in
	# the FINAL .config (post-patch, post-merge) and that the Kconfig
	# defaults are patched. The original defect was the build silently
	# re-enabling enforcement; this fails the build before compiling
	# if it ever recurs. A signed db may still ship -- it must simply
	# never be required.
	. "$SIB/check-regdb-freedom.sh"
	check_regdb_freedom "$SRC/linux-${kernel_version}/.config" \
		"$SRC/linux-${kernel_version}/net/wireless/Kconfig"
	# No-initramfs builtin policy: drivers stay built in (early
	# firmware/microcode images carry bytes only, no drivers - see
	# Boot path policy exception 2026-10-23), so
	# every root/console/network driver must be =y, not =m. olddefconfig
	# silently resolves new and changed symbols to defaults, which is how
	# a required builtin would be lost without anyone touching the config.
	# This gate fails the build before the compile, not after publication.
	. "$SIB/check-no-initramfs-builtins.sh"
	check_no_initramfs_builtins "$SRC/linux-${kernel_version}/.config" "$kernel_version"
	# Generated headers for the ZFS configure version probe
	# (olddefconfig alone does not emit utsrelease.h; without it
	# configure dies "Cannot find UTS_RELEASE definition").
	(cd "$SRC/linux-${kernel_version}" && make prepare) ||
		{ echo "ERROR: kernel prepare failed (ZFS configure needs generated headers)" >&2; return 1; }
	[ -f "$SRC/linux-${kernel_version}/include/generated/utsrelease.h" ] ||
		{ echo "ERROR: utsrelease.h missing after prepare" >&2; return 1; }

	# OpenZFS integration (upstream copy-builtin machinery): the five
	# 000* compat patches first (same set, same order, same exactness
	# rules as saphira-zfs-7.3: --forward so re-runs are safe, any fuzz
	# or offset fails the build rather than shipping drift), then
	# autogen (the patches touch config/*.m4, so the shipped configure
	# predates them), then configure against this tree with the kernel
	# config only (--with-config=kernel runs the kernel API probes
	# whose HAVE_* results the in-tree build consumes, and skips every
	# userspace check), plus --enable-linux-experimental (upstream's
	# designed escape hatch past ZFS_META_KVER_MAX; changes no code
	# paths, only an honest EXPERIMENTAL dmesg warning), then copy the
	# sources into the kernel tree.
	ZDIR="$RECIPE_DIR/../saphira-zfs-7.3/files"
	ZBALL="$ZDIR/zfs-${zfs_version}.tar.gz"
	[ -f "$ZBALL" ] ||
		{ echo "ERROR: no sibling zfs-${zfs_version}.tar.gz in saphira-zfs-7.3/files" >&2; return 1; }
	(cd "$ZDIR" && sha256sum -c "zfs-${zfs_version}.tar.gz.sha256") ||
		{ echo "ERROR: OpenZFS tarball failed its sha256 sidecar" >&2; return 1; }
	# Compat patches are vendored in files/ (see PATCHES.md), owned by
	# this recipe, same set/order/exactness as the kmod line.
	ZPATCHES="$RECIPE_DIR/files"
	mkdir -p "$SRC/zfs"
	tar --no-same-owner -C "$SRC/zfs" --strip-components=1 -xf "$ZBALL"
	cd "$SRC/zfs"
	[ -x ./copy-builtin ] ||
		{ echo "ERROR: OpenZFS tree has no copy-builtin (builtin integration unsupported at ${zfs_version}?)" >&2; return 1; }
	for patch in "$ZPATCHES"/000*.patch; do
		patch -p1 --forward < "$patch" > "$SRC/zfs/patch.log" 2>&1 || {
			echo "ERROR: 7.3 compat patch failed: ${patch##*/}" >&2
			tail -5 "$SRC/zfs/patch.log" >&2
			return 1
		}
		if grep -qE 'fuzz|offset' "$SRC/zfs/patch.log"; then
			echo "ERROR: ${patch##*/} applied loosely (fuzz/offset): rebase it, do not ship drift" >&2
			grep -E 'fuzz|offset' "$SRC/zfs/patch.log" >&2
			return 1
		fi
	done
	./autogen.sh || return 1
	# layout-exception: --with-config=kernel builtin mode copies
	# ZFS into the kernel tree; nothing installs to prefix,
	# sysconfdir or localstatedir, so dir flags are meaningless here.
	./configure --with-linux="$SRC/linux-${kernel_version}" \
		--with-linux-obj="$SRC/linux-${kernel_version}" \
		--with-config=kernel --enable-linux-builtin \
		--enable-linux-experimental || return 1
	./copy-builtin "$SRC/linux-${kernel_version}" || return 1
	cd "$SRC/linux-${kernel_version}"

	# Variant identity + ZFS, then re-resolve: copy-builtin adds new
	# Kconfig symbols, so olddefconfig must run again after it.
	./scripts/config --set-str CONFIG_LOCALVERSION "$zfs_localversion" \
		--enable CONFIG_ZFS || return 1
	make olddefconfig
	[ "$(./scripts/config --state CONFIG_ZFS)" = "y" ] ||
		{ echo "ERROR: CONFIG_ZFS is not =y after integration (copy-builtin Kconfig hook drift?)" >&2; return 1; }
	grep -q '^# CONFIG_ZFS_DEBUG is not set' .config ||
		{ echo "ERROR: CONFIG_ZFS_DEBUG got enabled (development assertions must never ship)" >&2; return 1; }
	grep -q "^CONFIG_LOCALVERSION=\"$zfs_localversion\"$" .config ||
		{ echo "ERROR: LOCALVERSION suffix missing (variant would collide with the official line)" >&2; return 1; }
	# Re-prove both policy gates on the FINAL .config: integration must
	# not have disturbed them.
	. "$SIB/check-regdb-freedom.sh"
	check_regdb_freedom "$SRC/linux-${kernel_version}/.config" \
		"$SRC/linux-${kernel_version}/net/wireless/Kconfig"
	. "$SIB/check-no-initramfs-builtins.sh"
	check_no_initramfs_builtins "$SRC/linux-${kernel_version}/.config" "$kernel_version"

	# Strip CFI directives from ZFS assembly: hand-written crypto asm
	# is full of .cfi_startproc etc., and gas turns those into
	# .eh_frame, which has no vmlinux.lds placement and dies as an
	# unplaced orphan under the official =error strictness (proven on
	# the 7.2.3 variant: identical five objects). Kernel asm carries
	# almost none in the ORC era and nothing in-kernel consumes
	# .eh_frame, so this changes no behaviour. Fail-closed both
	# directions: files must exist to strip, and none may remain.
	_cfifiles=$(grep -rl '^[[:space:]]*\.cfi_' fs/zfs --include='*.S')
	[ -n "$_cfifiles" ] ||
		{ echo "ERROR: no .cfi directives found under fs/zfs (unexpected; upstream removed them?)" >&2; return 1; }
	printf '%s\n' "$_cfifiles" | while IFS= read -r _f; do
		sed -i '/^[[:space:]]*\.cfi_/d' "$_f" || exit 1
	done || return 1
	if grep -rn '^[[:space:]]*\.cfi_' fs/zfs --include='*.S'; then
		echo "ERROR: .cfi directives remain under fs/zfs after stripping" >&2
		return 1
	fi
	make -j${JOBS:-$(nproc)} || return 1
	# Prove it: no .eh_frame may reach vmlinux (guards future ZFS
	# updates adding new CFI asm, and proves the =error strictness the
	# official line demands still holds here).
	if readelf -S vmlinux 2>/dev/null | grep -q eh_frame; then
		echo "ERROR: vmlinux carries .eh_frame (CFI stripping failed)" >&2
		return 1
	fi

}

recipe_install()
{
	# INSTALL_MOD_STRIP=1 is the kernel's own module-install stripping
	# mechanism, used here as a defence in depth behind the config-level
	# debug policy (mirrors the official line).
	make INSTALL_MOD_PATH="$PKGDEST" INSTALL_MOD_STRIP=1 modules_install
	# KREL is the true kernel release INCLUDING the -zfs LOCALVERSION
	# suffix (differs from kernel_version by design: co-installability
	# with the official line). Every /boot name and the module dir
	# follow KREL, never the bare version -- and never any release
	# suffix beyond the variant discriminator.
	. "$RECIPE_DIR/../saphira-kernel-${kernel_version}/files/install-kernel-layout.sh"
	KREL=$(kernel_layout_release "$SRC/linux-${kernel_version}")
	# KREL is the tree's own kernelrelease plus LOCALVERSION: 7.3 ->
	# 7.3.0-zfs (SUBLEVEL 0 always prints), 7.3.1 would give
	# 7.3.1-zfs. The -zfs suffix is what guarantees no collision with
	# the official line, so assert the shape, not one literal.
	case "$KREL" in
	${kernel_version}.*-zfs) ;;
	*) echo "ERROR: variant KREL is $KREL, want ${kernel_version}.*-zfs (LOCALVERSION lost?)" >&2; return 1 ;;
	esac
	install -d "$PKGDEST/boot"
	install -m 644 "$SRC/linux-${kernel_version}/arch/x86/boot/bzImage" "$PKGDEST/boot/vmlinuz-${KREL}"
	install -m 644 "$SRC/linux-${kernel_version}/System.map" "$PKGDEST/boot/System.map-${KREL}"
	install -m 644 "$SRC/linux-${kernel_version}/.config" "$PKGDEST/boot/config-${KREL}"
	# /boot naming assertion (local, exact): the shared boot-name gate
	# mandates the official -akadata suffix and must not be weakened to
	# admit this package, so the three exact names are asserted here
	# instead. Fails the stage on any stray name; report-only, never
	# deletes.
	for _want in "vmlinuz-$KREL" "System.map-$KREL" "config-$KREL"; do
		[ -f "$PKGDEST/boot/$_want" ] ||
			{ echo "ERROR: expected /boot/$_want missing" >&2; return 1; }
	done
	[ "$(ls "$PKGDEST/boot" | wc -l)" -eq 3 ] ||
		{ echo "ERROR: stray /boot payload names:" >&2; ls "$PKGDEST/boot" >&2; return 1; }
	[ ! -e "$PKGDEST/boot/vmlinuz" ] ||
		{ echo "ERROR: bare unversioned vmlinuz (never emitted by packaging)" >&2; return 1; }
	# Runtime package: no /usr/src, no prepared tree, no build/source
	# symlink -- not even dangling (mirrors the official line).
	rm -f "$PKGDEST/lib/modules/$KREL/build" "$PKGDEST/lib/modules/$KREL/source"
	check_module_layout "$PKGDEST" "$KREL" "$KREL"
	depmod -b "$PKGDEST" $KREL
	# Payload-carried honesty: this kernel is Andrew's personal
	# experimental build, not an official Saphira release; the binary
	# contains CDDL objects; publication is a separate decision. The
	# 7.3 line additionally carries the five compat patches and the
	# experimental flag, all disclosed here.
	install -d "$PKGDEST/usr/share/doc/$pkgname"
	cat > "$PKGDEST/usr/share/doc/$pkgname/README" <<EOF
andrews-kernel: Andrew's personal experimental Linux kernel (KREL $KREL).

Independent of AKADATA branding and Saphira's official kernel
releases; Saphira provides only the build infrastructure. No release
suffixes, no official status.

vmlinux contains OpenZFS ${zfs_version} compiled in (CONFIG_ZFS=y) via
upstream copy-builtin, plus the five 7.3 compat patches (0001/0002/
0003/0005/0006, same set as saphira-zfs-7.3) and
--enable-linux-experimental (honest EXPERIMENTAL dmesg warning for a
first-to-7.3 attempt). OpenZFS is CDDL-licensed; the rest of the kernel
is GPLv2. Building this package combines them locally at build time.
Publication of the built binary is a separate operator release
decision (signing is manual and operator-only): this recipe existing
does not approve it.

Co-installable with saphira-kernel-${kernel_version} (distinct KREL,
vermagic, /boot names and module dir). External kmod packages built
for KREL ${kernel_version} refuse to load here by vermagic, by design.
Milestone (a) only: the driver is present at boot. Pool import and
root-dataset mounting without initramfs is a separate milestone and
is NOT provided by this revision.
EOF
	# Declared maintainer hooks: regenerate the boot configuration after
	# the /boot payload lands (mirrors the official line; the hooks are
	# release-agnostic infrastructure).
	install -d -m 0755 "$PKGDEST/usr/share/saphira/hooks.d/$pkgname"
	install -m 0755 "$RECIPE_DIR/../saphira-kernel-${kernel_version}/files/hooks-grub-mkconfig" \
		"$PKGDEST/usr/share/saphira/hooks.d/$pkgname/post-install"
	install -m 0755 "$RECIPE_DIR/../saphira-kernel-${kernel_version}/files/hooks-grub-mkconfig" \
		"$PKGDEST/usr/share/saphira/hooks.d/$pkgname/post-upgrade"
	install -m 0755 "$RECIPE_DIR/../saphira-kernel-${kernel_version}/files/hooks-grub-mkconfig" \
		"$PKGDEST/usr/share/saphira/hooks.d/$pkgname/post-deinstall"
	# Early-firmware images for the same three moments (mirrors official).
	install -m 0755 "$RECIPE_DIR/../saphira-kernel-${kernel_version}/files/hooks-earlyfw" \
		"$PKGDEST/usr/share/saphira/hooks.d/$pkgname/post-install"
	install -m 0755 "$RECIPE_DIR/../saphira-kernel-${kernel_version}/files/hooks-earlyfw" \
		"$PKGDEST/usr/share/saphira/hooks.d/$pkgname/post-upgrade"
	install -m 0755 "$RECIPE_DIR/../saphira-kernel-${kernel_version}/files/hooks-earlyfw" \
		"$PKGDEST/usr/share/saphira/hooks.d/$pkgname/post-deinstall"
}
