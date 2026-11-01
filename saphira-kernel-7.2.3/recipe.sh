#!/bin/sh

pkgname=saphira-kernel-7.2.3
# Versioned kernel identity: one recipe directory per supported kernel
# line, pkgname carrying $kver, so apk treats kernel versions as
# independently installable packages instead of revisions of one
# package. 7.1.5, 7.2.2, 7.2.3 and 7.3-rc1 coexist indefinitely;
# installing one must never purge another's /boot or /lib/modules.
# Within this line, revisions supersede normally (r2 replaces r1).
#
# kernel_version is FIXED per directory (no SAPHIRA_KERNEL_VERSION
# override): the payload is named after the kernel, and config,
# tarball, patches and KREL all follow it. pkgver is the apk-legal
# form (hyphens before -rN are forbidden, so rc lines use underscore).
# This directory continues the 7.2.3 lineage previously built from the
# single-name saphira-kernel recipe; there is no replaces= handover --
# legacy migration is an explicit ownership transfer (T7), never an
# automatic replacement.
kernel_version=7.2.3
pkgver=1
pkgrel=17
# r15: earlyfw refresh hook honors the opt-in marker (generation only
# on opted machines; grub regen stays unconditional). Payload change.
# r13: framebuffer console capability completion (2026-10-23):
# FRAMEBUFFER_CONSOLE_DETECT_PRIMARY=y (the only requested symbol the
# line lacked; verified present in 7.1.5..7.3 Kconfig), gate requires
# VIRTIO, DRM_I915, DRM_KMS_HELPER, DRM_SIMPLEDRM, DRM_VIRTIO_GPU_KMS
# (all already =y). Capabilities only - console selection stays outside
# the kernel. Payload + gate change.
# r12: SEV1 console correction (2026-10-23): built kernels define NO
# command line at all (the r11 console=tty0 built-in still dictated
# console policy from the kernel package; the bootloader owns the entire
# line). CONFIG_CMDLINE_BOOL unset, CONFIG_CMDLINE empty, gate extended.
# Payload change.
# r11: SEV1 console contract (2026-10-23): CONFIG_CMDLINE names exactly
# console=tty0 (the packaged dual line handed /dev/console to a serial
# port and blinded VGA boots, last-console-wins). Build gate extended.
# Payload change.
# r10: CONFIG_XFS_FS=y (XFS root support; same built-in philosophy as
# ext4/btrfs). Gate extended. Payload change.
# r9: BTRFS_FS=y + BTRFS_FS_POSIX_ACL=y (btrfs root support; no
# initramfs means the filesystem must be built in, not a module).
# Gate extended. Payload change.
# r6: origin="$pkgname" (version-specific identity end to end; no
# generic saphira-kernel origin for independently versioned kernel
# packages). Metadata change, revision bump.
# r5: hypervisor programme (task 55f2235d): KVM_AMD=m, KVM_XEN=y,
# full Xen Dom0/DomU set (core/console/root-path frontends =y,
# backends + rest =m; TARGET_CORE/TCG_TPM=m prerequisites).
# Verified per line with olddefconfig. Payload change.
# r4: build in DRM_BOCHS + DRM_QXL (QEMU std VGA and SPICE consoles
# need builtin drivers; no general initramfs to load them (early
# firmware/microcode images excepted, 2026-10-23). Payload change.
# r2: enable DRM_FBDEV_EMULATION (KMS drivers took over the VGA console
# and showed nothing: proven blind on N100/i915 with efifb handoff and
# no fbcon ever appearing). Payload change.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Saphira kernel 7.2.3 (x86-64-v3, signed modules, Saphira regdb trust)"
license=GPL-2.0-only
origin="$pkgname"
repo=saphira
url=https://saphira.vm2.uk/

# RELEASE NOTE (size policy): the 7.2.2 line carries a permanent release
# note about its r7-r9 oversized artefacts; see saphira-kernel-7.2.2.
# This line follows the same policy (CONFIG_DEBUG_INFO_NONE=y, no
# /usr/src, no build/source symlinks, INSTALL_MOD_STRIP=1).
# Upstream kernel tarball for this line (kernel.org signs the UNCOMPRESSED
# .tar; verify procedure: xz -dc file.xz > file.tar && gpg --verify
# file.tar.sign file.tar).
vendor=https://mirrors.edge.kernel.org/pub/linux/kernel/v7.x/linux-7.2.3.tar.xz
sha256=8ba259e8e7b13ec6ef0941c8a39ad90b24bd4a4d6c0010ba6bafb794550ecd03

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
"
# pahole is required by CONFIG_DEBUG_INFO_BTF, which this line's config
# enables. BTF generation is not optional garnish: it is what lets a
# vmlinux.h be derived from THIS kernel, which systemd's BPF
# userns-restriction program needs in order to be built. elfutils-dev was
# already here for other reasons; pahole itself is the new input. The
# config records CONFIG_PAHOLE_VERSION=131, so the build detects the tool
# at build time and a missing or older pahole shows up as BTF silently
# not being generated -- hence it is a hard makedepends entry rather than
# a note.
#
# zlib-dev has the same kind of evidence behind it, and the same reason to
# be a hard entry rather than a note. Enabling BTF makes the kernel build
# tools/bpf/resolve_btfids, which compiles the bundled libbpf, and
# tools/lib/bpf/libbpf.c includes <zlib.h> (and <libelf.h>/<gelf.h>, which
# elfutils-dev already provides). Without it the build died at
# libbpf.c:48: fatal error: zlib.h: No such file or directory.

# Build inputs: none beyond the recipe tree. The module signing key is
# exposed by the builder (fixed in-namespace path); no /input staging.
# Regdb trust: public DER cert ships in files/ and is compiled into cfg80211
# via CONFIG_CFG80211_EXTRA_REGDB_KEYDIR. Saphira policy patches live in
# files/: x86-64-v3.patch, config-${kernel_version}-akadata. Note these
# follow kernel_version: the payload is named after the KERNEL, and
# config-<kver>-akadata is the name the layout gate, the kmod
# provenance gate and the release guard all look for.

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

	# Local archive wins when present (verified, never re-downloaded);
	# otherwise build from the builder-verified $SOURCE_ARCHIVE.
	KBALL="$RECIPE_DIR/files/linux-${kernel_version}.tar.xz"
	[ -f "$KBALL" ] || KBALL="$RECIPE_DIR/files/linux-${kernel_version}.tar.gz"
	if [ -f "$KBALL" ]; then
		echo "$sha256  $KBALL" | sha256sum -c -
	else
		[ -n "${SOURCE_ARCHIVE-}" ] && [ -f "$SOURCE_ARCHIVE" ] \
			|| { echo "ERROR: no local linux-${kernel_version}.tar.{xz,gz} and no fetched SOURCE_ARCHIVE" >&2; return 1; }
		KBALL=$SOURCE_ARCHIVE
	fi
	mkdir -p "$SRC/linux-${kernel_version}"
	tar --no-same-owner -C "$SRC/linux-${kernel_version}" --strip-components=1 -xf "$KBALL"
	cd "$SRC/linux-${kernel_version}"

	patch -Np1 -i "$RECIPE_DIR/files/x86-64-v3.patch" > "$SRC/patch-v3.log" 2>&1 || return 1
	# Strict application: this copy carries exact upstream context for its
	# line, so any fuzz or offset is drift, not tolerance. Fail closed
	# rather than shipping a loosely applied baseline.
	if grep -qE 'fuzz|offset' "$SRC/patch-v3.log"; then
		echo "ERROR: x86-64-v3.patch applied loosely (fuzz/offset): rebase it, do not ship drift" >&2
		grep -E 'fuzz|offset' "$SRC/patch-v3.log" >&2
		return 1
	fi
	# Regulatory freedom (article: kernel must not mandate regdb
	# signatures): flip the two gatekeeper Kconfig defaults y -> n so
	# an absent symbol can never resolve to enforced verification.
	# Fails closed on upstream drift like the v3 patch. The recipe
	# config carries both symbols as explicit "is not set"; the gate
	# below proves the final .config after olddefconfig.
	patch -Np1 -i "$RECIPE_DIR/files/cfg80211-regdb-freedom.patch" > "$SRC/patch-freedom.log" 2>&1 || return 1
	# Strict application, same rule as the v3 patch above.
	if grep -qE 'fuzz|offset' "$SRC/patch-freedom.log"; then
		echo "ERROR: cfg80211-regdb-freedom.patch applied loosely (fuzz/offset): rebase it, do not ship drift" >&2
		grep -E 'fuzz|offset' "$SRC/patch-freedom.log" >&2
		return 1
	fi
	# CVE-2026-98432 (9.8 CRITICAL, IPv4 TCP use-after-free): free
	# inet_opt and ireq_opt after an RCU grace period (kfree ->
	# kfree_rcu in inet_sock_destruct and tcp_v4_reqsk_destructor).
	# Matches the fix already upstream in 7.3; verified absent here
	# by source inspection. Fails closed on context drift.
	patch -Np1 -i "$RECIPE_DIR/files/cve-2026-98432-ipv4-reqsk-rcu.patch"
	cp "$RECIPE_DIR/files/config-${kernel_version}-akadata" "$SRC/linux-${kernel_version}/.config"
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
	. "$RECIPE_DIR/files/check-regdb-freedom.sh"
	check_regdb_freedom "$SRC/linux-${kernel_version}/.config" \
		"$SRC/linux-${kernel_version}/net/wireless/Kconfig"
	# No-initramfs builtin policy: drivers stay built in (early
# firmware/microcode images carry bytes only, no drivers - see
# Boot path policy exception 2026-10-23), so
	# every root/console/network driver must be =y, not =m. olddefconfig
	# silently resolves new and changed symbols to defaults, which is how
	# a required builtin would be lost without anyone touching the config.
	# This gate fails the build before the compile, not after publication.
	. "$RECIPE_DIR/files/check-no-initramfs-builtins.sh"
	check_no_initramfs_builtins "$SRC/linux-${kernel_version}/.config" "$kernel_version"
	make -j${JOBS:-$(nproc)}

}

recipe_install()
{
	# INSTALL_MOD_STRIP=1 is the kernel's own module-install stripping
	# mechanism, used here as a defence in depth behind the config-level
	# debug policy. It is not redundant: the config asserts no DWARF is
	# generated at all, while this guarantees no debug payload reaches a
	# runtime .ko even if some future config or toolchain reintroduces it.
	# Previously the package was assembled with a bare modules_install, so
	# whatever the build produced shipped verbatim -- which is how 218
	# modules totalling 745 MiB were published in r7-r9.
	make INSTALL_MOD_PATH="$PKGDEST" INSTALL_MOD_STRIP=1 modules_install
	install -d "$PKGDEST/boot"
	install -m 644 "$SRC/linux-${kernel_version}/arch/x86/boot/bzImage" "$PKGDEST/boot/vmlinuz-${kernel_version}-akadata"
	install -m 644 "$SRC/linux-${kernel_version}/System.map" "$PKGDEST/boot/System.map-${kernel_version}-akadata"
	install -m 644 "$SRC/linux-${kernel_version}/.config" "$PKGDEST/boot/config-${kernel_version}-akadata"
	# /boot image naming policy: vmlinuz-<kver>-akadata exactly, no
	# suffixes (revisions live in the APK NVR, never the filename).
	# Fails the stage on any stray name; report-only, never deletes.
	. "$RECIPE_DIR/files/check-boot-image-names.sh"
	check_boot_image_names "$PKGDEST" "$kernel_version"
	# saphira-kernel-7.2.3 is a RUNTIME package. Upstream modules_install bakes the
	# absolute build-tree path into lib/modules/<release>/{build,source};
	# constructor state under /build must never leak into an installed
	# filesystem. This package used to resolve that by SHIPPING the prepared
	# tree at /usr/src/linux-<pkgver>-saphira and pointing build at it, which
	# put 1648 MiB and 77,655 files of kernel source into a runtime APK and
	# grew every installed rootfs to roughly 3 GiB.
	#
	# It does not: no /usr/src, no prepared tree, no build/source symlink --
	# not even dangling, because a link that can only dangle is a trap for
	# whoever debugs the next thing. An out-of-tree module build is a
	# BUILD-TIME concern and belongs to the builder, which prepares its own
	# tree from the vendored tarball and config. No replacement kernel-build
	# package is introduced here either: a public runtime distribution must
	# not become a build workstation by accident.
	#
	# KREL is the true kernel release (differs from pkgver on -rc lines);
	# depmod and the module dir both use it.
	. "$RECIPE_DIR/files/install-kernel-layout.sh"
	KREL=$(kernel_layout_release "$SRC/linux-${kernel_version}")
	# Upstream modules_install itself creates lib/modules/<rel>/build and
	# lib/modules/<rel>/source as symlinks to the absolute build tree under
	# /build. Deleting them is not cosmetic: they are constructor state
	# pointing outside the package, and /build does not exist on an
	# installed system. They are removed here rather than repointed, because
	# there is no legitimate runtime target for them and a link that can
	# only dangle misleads whoever debugs the next thing. check_module_layout
	# asserts their absence, so this cannot be undone by accident.
	rm -f "$PKGDEST/lib/modules/$KREL/build" "$PKGDEST/lib/modules/$KREL/source"
	check_module_layout "$PKGDEST" "$KREL" "$KREL"
	depmod -b "$PKGDEST" $KREL
	# Declared maintainer hooks: regenerate the boot configuration after
	# the /boot payload lands. Install, upgrade AND deinstall all need
	# it: an upgrade used to leave the old kernel in the menu, and a
	# removal without regeneration leaves a dead menu entry behind.
	# makepkg embeds these into the package lifecycle scripts and strips
	# this declaration from the payload, so the generated script is the
	# only shipped copy.
	install -d -m 0755 "$PKGDEST/usr/share/saphira/hooks.d/$pkgname"
	install -m 0755 "$RECIPE_DIR/files/hooks-grub-mkconfig" \
		"$PKGDEST/usr/share/saphira/hooks.d/$pkgname/post-install"
	install -m 0755 "$RECIPE_DIR/files/hooks-grub-mkconfig" \
		"$PKGDEST/usr/share/saphira/hooks.d/$pkgname/post-upgrade"
	install -m 0755 "$RECIPE_DIR/files/hooks-grub-mkconfig" \
		"$PKGDEST/usr/share/saphira/hooks.d/$pkgname/post-deinstall"
	# Early-firmware images for the same three moments (2026-10-23):
	# built-in drivers need their blobs before the root mount, so every
	# kernel arrival/departure regenerates initramfs-<release>.img for
	# all installed kernels (plus pruning) via saphira-earlyfw, which
	# also regenerates grub.cfg. Same hooks.d mechanism, same contract
	# (absent generator/grub are legitimate no-ops, failures are loud).
	install -m 0755 "$RECIPE_DIR/files/hooks-earlyfw" \
		"$PKGDEST/usr/share/saphira/hooks.d/$pkgname/post-install"
	install -m 0755 "$RECIPE_DIR/files/hooks-earlyfw" \
		"$PKGDEST/usr/share/saphira/hooks.d/$pkgname/post-upgrade"
	install -m 0755 "$RECIPE_DIR/files/hooks-earlyfw" \
		"$PKGDEST/usr/share/saphira/hooks.d/$pkgname/post-deinstall"
}
