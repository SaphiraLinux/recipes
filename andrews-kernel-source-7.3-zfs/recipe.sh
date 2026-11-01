pkgname=andrews-kernel-source-7.3-zfs
pkgver=1
pkgrel=1
# r1: first revision. Pristine source input for the andrews 7.3 line
# (KREL 7.3.0-zfs, derived via `make kernelrelease`, never hand-written).
#
# UNIQUENESS (read before touching): this package carries upstream 7.3
# source plus the one deliberate Saphira source patch
# (x86-64-v3, the shipped CPU baseline). It does NOT carry ZFS: ZFS is
# builtin to andrews-kernel-7.3 via upstream copy-builtin at BUILD time
# (five 000* compat patches + --enable-linux-builtin +
# --enable-linux-experimental, owned by andrews-kernel-7.3/files), so
# the source package stays pristine and the builtin integration stays
# exactly where it is verifiable -- in the worker, under /build.
#
# WHAT THIS PACKAGE IS, AND WHAT IT IS NOT (same invariant as
# saphira-kernel-source-7.3, from which this recipe is cloned):
#
#     kernel build tree  !=  kernel source package input
#
# Nothing here compiles. There is no build tree in this workspace for
# build output to leak from, so the invariant is STRUCTURAL rather than
# defended by a prune list.
#
# It is NOT an external-module build tree, and it does not claim to be.
# .config, Module.symvers, include/generated, built scripts (modpost,
# sign-file) and key material are all build output and are all absent
# here by construction. NVIDIA and gpu-unlock builds against KREL
# 7.3.0-zfs consume this source THROUGH the worker-side prepared tree
# contract (saphira-kernel/files/kmod-andrews.sh), which reproduces the
# exact configuration, ZFS integration, generated headers, scripts and
# a provenanced Module.symvers under /build -- never from this payload.
# That contract is deliverable 1; module packaging follows only after
# its ABI verification gate passes.
#
# Nothing depends on this package at runtime: it is a build-side input,
# deliberately not a dependency of any runtime profile, so no installed
# rootfs and no published image ever carries it.
#
# KREL-EXACTNESS: install path carries the full derived release
# (linux-7.3.0-zfs-saphira), not the 7.3 shorthand the old recipe
# comments use. A future SUBLEVEL bump (7.3.1-zfs) is a new recipe
# directory, never an edit of this one's paths.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Andrew's kernel 7.3 source tree for KREL 7.3.0-zfs (upstream 7.3 + Saphira x86-64-v3 patch; no build output)"
license='GPL-2.0-only'
origin="$pkgname"
repo=saphira
url=https://saphira.vm2.uk/

depends=""
# No compiler is involved: nothing is built, so there is no gcc, no pahole, no
# elfutils, no binutils, no kernel UAPI headers to satisfy. What is genuinely
# needed: read the vendored tarball, verify it, extract it, apply one patch,
# copy a tree.
makedepends="
  coreutils
  gawk
  patch
  tar
  xz
  gzip
  zstd
"
# The vendored archive is the same verified tarball andrews-kernel-7.3 and
# saphira-kernel-7.3 compile. Read as the sibling recipe's vendored copy so
# the trees cannot drift: the sha256 below is cross-checked against
# saphira-kernel-7.3's own pin at build time, which is the assertion that
# this source and both kernels are the same upstream bytes.

recipe_build()
{
	export TAR_OPTIONS=--no-same-owner

	KVER=7.3
	KBASE="$RECIPE_DIR/../saphira-kernel-$KVER/files/linux-$KVER"
	KBALL="$KBASE.tar.xz"
	[ -f "$KBALL" ] || {
		echo "ERROR: no vendored linux-$KVER.tar.xz" >&2
		return 1
	}
	# Verify the archive against its own sidecar, without parsing it.
	(cd "$(dirname "$KBALL")" && sha256sum -c "$(basename "$KBALL").sha256") ||
		{ echo "ERROR: $(basename "$KBALL") failed its sha256 sidecar" >&2; return 1; }
	# And prove it is the SAME archive saphira-kernel-7.3 pins (the pin
	# andrews-kernel-7.3 also compiles: both kernels share these bytes;
	# ZFS diverges only at build time via copy-builtin). A shared path
	# is not a shared hash: this is the assertion.
	kernel_sha=$(grep -m1 "^sha256=" \
		"$RECIPE_DIR/../saphira-kernel-$KVER/recipe.sh" | cut -d= -f2)
	side_sha=$(awk 'NR==1{print $1}' "$KBALL.sha256")
	[ -n "$kernel_sha" ] && [ "$kernel_sha" = "$side_sha" ] || {
		echo "ERROR: source tree archive does not match saphira-kernel-$KVER pin" >&2
		echo "  saphira-kernel: ${kernel_sha:-<none>}" >&2
		echo "  sidecar:        ${side_sha:-<none>}" >&2
		return 1
	}

	# A FRESH extraction into a directory of its own. Deliberately NOT $SRC:
	# $SRC is the shared recipe workspace, and $BUILDDIR is where a build
	# would live if this recipe built anything. Neither is used here, and
	# keeping the pristine tree in its own directory is what makes "this
	# package was never staged from a build tree" checkable rather than
	# merely asserted.
	PRISTINE="$BUILDDIR/pristine/linux-$KVER"
	rm -rf "$BUILDDIR/pristine"
	mkdir -p "$PRISTINE"
	tar --no-same-owner -C "$PRISTINE" --strip-components=1 -xf "$KBALL"
	[ -f "$PRISTINE/Makefile" ] || {
		echo "ERROR: extracted tree has no Makefile: $PRISTINE" >&2
		return 1
	}

	# The one intentional Saphira source patch. This is the ONLY modification
	# made to upstream source, and it is a deliberate architecture decision
	# (the shipped CPU baseline), not packaging fallout. Read as the andrews
	# recipe's own vendored copy (byte-identical to the official line's;
	# each line owns its inputs -- no symlinks between recipes).
	patch -Np1 --no-backup-if-mismatch -d "$PRISTINE" -i \
		"$RECIPE_DIR/../andrews-kernel-7.3/files/x86-64-v3.patch" > "$BUILDDIR/patch-v3.log" 2>&1 ||
		{ echo "ERROR: x86-64-v3.patch did not apply" >&2; return 1; }
	# Strict application (exact 7.3 context): fuzz or offset is drift.
	if grep -qE 'fuzz|offset' "$BUILDDIR/patch-v3.log"; then
		echo "ERROR: x86-64-v3.patch applied loosely (fuzz/offset): rebase it, do not ship drift" >&2
		grep -E 'fuzz|offset' "$BUILDDIR/patch-v3.log" >&2
		return 1
	fi

	# Deliberately NOT done here, and each omission is load-bearing:
	#   - no .config            a source package carries no configuration
	#   - no certs/regdb, no signing key   key material is build-time only
	#   - no ZFS copy-builtin   builtin integration is a build-time act
	#   - no make olddefconfig   nothing is compiled
	#   - no make                see the header: this is the whole fix
	#
	# Verify the staged input BEFORE it reaches the payload, so a
	# contamination ever introduced here fails the build naming the file
	# rather than shipping.
	. "$RECIPE_DIR/../saphira-kernel/files/kernel-source-tree.sh"
	check_source_tree_pure "$PRISTINE"
}

recipe_install()
{
	. "$RECIPE_DIR/../saphira-kernel/files/kernel-source-tree.sh"
	# KREL-exact destination: the full derived release, matching the
	# module directory the kernel ships (/lib/modules/7.3.0-zfs).
	# install_module_build_link is deliberately NOT used: that link belongs
	# to a kernel package owning a module directory, and this package ships
	# no modules at all.
	install_clean_source_tree "$BUILDDIR/pristine/linux-7.3" \
		"$PKGDEST/usr/src/linux-7.3.0-zfs-saphira"
	# No /lib/modules/<rel>/build link, deliberately. That link belongs to
	# a kernel package, which this is not.
}
