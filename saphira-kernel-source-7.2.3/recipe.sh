pkgname=saphira-kernel-source-7.2.3
pkgver=1
pkgrel=4
# r3: STOP BUILDING THE KERNEL TO PACKAGE ITS SOURCE. r2 tracked
# saphira-kernel-7.2.3 r2 (CONFIG_DRM_FBDEV_EMULATION=y); r3 replaces the
# whole staging contract, so the r2 payload description no longer applies.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Saphira kernel 7.2.3 source tree (upstream 7.2.3 + Saphira x86-64-v3 patch; no build output)'
license='GPL-2.0-only'
origin=saphira-kernel-source-7.2.3
repo=saphira
url=https://saphira.vm2.uk/

# r2: STOP BUILDING THE KERNEL TO PACKAGE ITS SOURCE.
#
# r1 was assembled from a USED KERNEL BUILD TREE, not from source. buildpkg-single
# runs recipe_build and recipe_install against one $SRC, and r1's recipe_build ran
# `make olddefconfig && make -j$(nproc)` there before recipe_install copied that
# same directory into the payload. install_prepared_tree() then pruned a DENYLIST
# of the names someone remembered, so everything it did not name shipped:
#
#     Module.symvers      .config              vmlinux.unstripped
#     arch/x86/boot/bzImage                      boot/compressed/vmlinux.bin*
#     include/config/    (2,395 entries)       include/generated/
#     scripts/sign-file  scripts/mod/modpost   tools/objtool/fixdep   (built host tools)
#     lib/lib.a          lib.a x4              usr/gen_init_cpio
#     modules.order      (834 entries)         .tmp_missing-syscalls
#
# Measured on the published saphira-kernel-source-7.2.3-1-r1.apk: 353,068,690 bytes
# compressed, installed-size 1,713,311,357. On 7.2.2 the payload carried 82,890 paths, of
# which 3,410 were absent from the upstream tarball entirely. A clean upstream 7.2.3
# tarball is 160,060,344 bytes.
#
# THE INVARIANT THIS RECIPE NOW ENFORCES
#
#     kernel build tree  !=  kernel source package input
#
# Nothing here compiles. There is no build tree in this workspace for build
# output to leak from, so the invariant is STRUCTURAL rather than defended by a
# prune list. A prune list is what failed: it is correct only for the names
# somebody thought of at the time, and every future kernel release adds build
# outputs nobody has seen yet.
#
# WHAT THIS PACKAGE IS, AND WHAT IT IS NOT
#
# It is upstream 7.2.3 source plus the one deliberate Saphira source patch
# (files/x86-64-v3.patch: -march=x86-64-v3 for the shipped CPU baseline). It is
# verified against the same vendored tarball and the same sha256 pin that
# saphira-kernel-7.2.3 compiles, so "the source for this kernel" is an assertion
# about bytes rather than about a filename.
#
# It is NOT an external-module build tree, and no longer claims to be. r1 shipped
# Module.symvers, .config and include/generated/ so that an out-of-tree module
# could be compiled against this exact configuration; that is precisely the set of
# things a SOURCE package must not contain, because they are all build output.
# Shipping them made the package 2.4x larger and made it a build tree with a
# source archive stapled on. If an external-module build against a live config is
# wanted, the builder prepares its own tree from the vendored tarball and the
# canonical config file; that is a build-time concern and it does not belong in a
# repository payload.
#
# Nothing depends on this package: saphira-zfs-7.2.3, nvidia-open-7.2.3 and
# saphira-drbd9-7.2.3 all depend on the RUNTIME saphira-kernel-7.2.3, and this
# package is deliberately not a dependency of any runtime profile, so no
# installed rootfs and no published image ever carries it.
#
# Renamed from saphira-kernel-devel-7.2.3 (same intent, versioned kernel-family
# identity; origin tracks identity).

depends=""
# No compiler is involved: nothing is built, so there is no gcc, no pahole, no
# elfutils, no binutils, no kernel UAPI headers to satisfy. r1 carried the whole
# saphira-kernel makedepends closure (14 packages, most of it unused) purely
# because it compiled a kernel in order to ship that kernel's source.
#
# What is genuinely needed: read the vendored tarball, verify it, extract it,
# apply one patch, copy a tree.
makedepends="
  coreutils
  gawk
  patch
  tar
  xz
  gzip
  zstd
"
# The vendored archive is the same verified tarball saphira-kernel-7.2.3 compiles.
# Read as the sibling recipe's vendored copy rather than fetched again, so the two
# cannot drift: the sha256 below is cross-checked against saphira-kernel-7.2.3's
# own pin at build time, which is the assertion that this tree and the running
# kernel are the same kernel rather than two builds of a similar name.

recipe_build()
{
	export TAR_OPTIONS=--no-same-owner

	KVER=7.2.3
	KBASE="$RECIPE_DIR/../saphira-kernel-$KVER/files/linux-$KVER"
	KBALL="$KBASE.tar.xz"
	# 7.3-rc1 is a .tar.gz (torvalds cgit snapshot); the rest are .tar.xz.
	[ -f "$KBALL" ] || KBALL="$KBASE.tar.gz"
	[ -f "$KBALL" ] || {
		echo "ERROR: no vendored linux-$KVER.tar.xz or .tar.gz" >&2
		return 1
	}
	# Verify the archive against its own sidecar, without parsing it.
	(cd "$(dirname "$KBALL")" && sha256sum -c "$(basename "$KBALL").sha256") ||
		{ echo "ERROR: $(basename "$KBALL") failed its sha256 sidecar" >&2; return 1; }
	# And prove it is the SAME archive saphira-kernel-7.2.3 pins. The two
	# recipes reading one vendored file is already shared, but a shared path
	# is not a shared hash: this is the assertion that the source package and
	# the running kernel are the same kernel.
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
	# (the shipped CPU baseline), not packaging fallout.
	patch -Np1 --no-backup-if-mismatch -d "$PRISTINE" -i \
		"$RECIPE_DIR/../saphira-kernel-$KVER/files/x86-64-v3.patch" > "$BUILDDIR/patch-v3.log" 2>&1 ||
		{ echo "ERROR: x86-64-v3.patch did not apply" >&2; return 1; }
	# Strict application (exact per-line context): fuzz or offset is drift.
	if grep -qE 'fuzz|offset' "$BUILDDIR/patch-v3.log"; then
		echo "ERROR: x86-64-v3.patch applied loosely (fuzz/offset): rebase it, do not ship drift" >&2
		grep -E 'fuzz|offset' "$BUILDDIR/patch-v3.log" >&2
		return 1
	fi

	# Deliberately NOT done here, and each omission is load-bearing:
	#   - no .config            a source package carries no configuration
	#   - no certs/regdb, no signing key   key material is build-time only
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
	KVER=7.2.3
	. "$RECIPE_DIR/../saphira-kernel/files/kernel-source-tree.sh"
	# install_clean_source_tree verifies the input, copies, then verifies the
	# destination, so both the source of truth and the copy are proven clean.
	install_clean_source_tree "$BUILDDIR/pristine/linux-$KVER" \
		"$PKGDEST/usr/src/linux-$KVER-saphira"
	# No /lib/modules/<rel>/build link, deliberately. That link belongs to
	# saphira-kernel, which owns the module directory; this package ships no
	# modules at all, and install_module_build_link correctly refuses a tree
	# with no /lib/modules/<rel> beneath it.
}