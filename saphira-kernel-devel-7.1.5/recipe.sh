pkgname=saphira-kernel-devel-7.1.5
pkgver=7.1.5
pkgrel=1
# LEGACY IDENTITY, DISABLED: superseded by saphira-kernel-source-7.1.5
# (same payload contract). Stays only as reference; must never build
# or publish again.
disabled=yes
disabled_reason='superseded by saphira-kernel-source-7.1.5 (versioned kernel-family identity; origin tracks identity)'
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Saphira kernel 7.1.5 external-module build tree (Kbuild: Makefile, Module.symvers, generated headers, modpost, sign-file)'
license='GPL-2.0-only'
origin=saphira-kernel
repo=saphira
url=https://saphira.vm2.uk/

# BUILD-SIDE ONLY. This package exists so an out-of-tree module (saphira-zfs-7.1.5,
# nvidia-open-7.1.5, saphira-drbd9-7.1.5) can be compiled against THIS kernel's
# exact configuration. It is deliberately NOT a dependency of saphira-kernel,
# saphira-kernel-headers or any runtime profile, so no installed rootfs and no
# published image ever carries it.
#
# It exists because saphira-kernel used to ship this tree in its own payload
# (d2e581d, +1648 MiB and +77,655 files), which grew every installed rootfs to
# roughly 3 GiB. The corrective r10 removed it from the runtime package
# outright. That left out-of-tree module builds with no tree to build against,
# and the answer is a separate build-side package rather than putting build
# content back into a runtime one.
#
# What an external module build actually reads, and therefore what this ships:
#   Makefile                 the kbuild entry point
#   .config                  the configuration the kernel was built with
#   Module.symvers           exported symbols (and CRCs, where enabled)
#   include/generated/**     autoconf.h and every compiler-derived header
#   include/config/kernel.release
#   scripts/mod/modpost      symbol resolution for the module
#   scripts/sign-file        module signing
#   scripts/, arch/          the kbuild machinery itself
# plus the kernel source, which an external build compiles against. That source
# is the bulk of the size and cannot be pruned away, which is precisely why this
# is a package nobody installs on a running system.
#
# The corrected helper stages a pristine extraction and refuses a contaminated
# one: see saphira-kernel/files/kernel-source-tree.sh. The denylist this
# identity used to rely on is what let build output through.

depends=""
# Inherited wholesale from saphira-kernel rather than curated separately.
# The devel tree compiles the same kernel, so it needs the same toolchain
# inputs -- elfutils-dev for gelf.h, which tools/objtool includes; pahole
# for CONFIG_DEBUG_INFO_BTF; zlib-dev for tools/bpf/resolve_btfids. A
# hand-picked subset is how the build died on a missing gelf.h.
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
  kmod
"
# No module signing key is required any more. This identity used to compile the
# kernel so it could ship a tree an external module could be built against, and
# that build signed nothing by itself but did stage the key's tree. It now stages
# pristine source, so requiring the key would make the builder demand a build
# secret for a package that never signs. The key is never staged and never
# copied into /recipes, and install_clean_source_tree refuses a tree carrying it.

recipe_build()
{
	export TAR_OPTIONS=--no-same-owner
	# 7.3-rc1 is a .tar.gz (torvalds cgit snapshot); the rest are .tar.xz.
	# Same fallback saphira-kernel uses, rather than hardcoding one spelling.
	KBALL="$RECIPE_DIR/../saphira-kernel/files/linux-7.1.5.tar.xz"
	[ -f "$KBALL" ] || KBALL="$RECIPE_DIR/../saphira-kernel/files/linux-7.1.5.tar.gz"
	[ -f "$KBALL" ] || { echo "ERROR: no vendored linux-7.1.5.tar.xz" >&2; return 1; }
	# Same archive and same sha256 pin as saphira-kernel. If these ever
	# diverge the devel tree and the running kernel stop being the same
	# kernel, which is the one thing this package exists to guarantee.
	# Verify the archive against its own sidecar, without parsing it.
	(cd "$(dirname "$KBALL")" && sha256sum -c "$(basename "$KBALL").sha256") ||
		{ echo "ERROR: $(basename "$KBALL") failed its sha256 sidecar" >&2; return 1; }
	# And prove it is the SAME archive saphira-kernel pins. The two recipes
	# reading one vendored file is already shared, but a shared path is not a
	# shared hash: this is the assertion that the devel tree and the running
	# kernel are the same kernel rather than two builds of a similar name.
	kernel_sha=$(sed -n '/^[[:space:]]*7.1.5)/,/;;/p' \
		"$RECIPE_DIR/../saphira-kernel/recipe.sh" | sed -n 's/^[[:space:]]*sha256=//p' | head -1)
	side_sha=$(awk 'NR==1{print $1}' "$(dirname "$KBALL")/linux-7.1.5.tar.xz.sha256")
	[ -n "$kernel_sha" ] && [ "$kernel_sha" = "$side_sha" ] || {
		echo "ERROR: devel tree source does not match saphira-kernel 7.1.5 pin" >&2
		echo "  saphira-kernel: ${kernel_sha:-<none>}" >&2
		echo "  sidecar:        ${side_sha:-<none>}" >&2
		return 1
	}

	# A FRESH extraction into a directory of its own. Deliberately NOT $SRC:
	# $SRC is the shared recipe workspace and $BUILDDIR is where a build would
	# live if this recipe built anything. Neither is used, and keeping the
	# pristine tree in its own directory is what makes "this package was never
	# staged from a build tree" checkable rather than merely asserted.
	PRISTINE="$BUILDDIR/pristine/linux-7.1.5"
	rm -rf "$BUILDDIR/pristine"
	mkdir -p "$PRISTINE"
	tar --no-same-owner -C "$PRISTINE" --strip-components=1 -xf "$KBALL"
	[ -f "$PRISTINE/Makefile" ] || {
		echo "ERROR: extracted tree has no Makefile: $PRISTINE" >&2
		return 1
	}

	# The one intentional Saphira source patch, and the ONLY modification made
	# to upstream source here.
	patch -Np1 --no-backup-if-mismatch -d "$PRISTINE" -i \
		"$RECIPE_DIR/../saphira-kernel/files/x86-64-v3.patch" ||
		{ echo "ERROR: x86-64-v3.patch did not apply" >&2; return 1; }

	# Deliberately NOT done here, and each omission is load-bearing: no
	# .config, no cert material, no `make`. This identity was disabled before
	# it was corrected, and it shared the r1 defect: it staged its payload from
	# a post-make tree and relied on install_prepared_tree()'s denylist to
	# remove the build output afterwards. The corrected helper stages from the
	# pristine tree and refuses a contaminated one outright, so the defect
	# cannot return if this recipe is ever re-enabled.
	. "$RECIPE_DIR/../saphira-kernel/files/kernel-source-tree.sh"
	check_source_tree_pure "$PRISTINE"
}

recipe_install()
{
	. "$RECIPE_DIR/../saphira-kernel/files/kernel-source-tree.sh"
	# Verifies the input, copies, then verifies the destination.
	install_clean_source_tree "$BUILDDIR/pristine/linux-7.1.5" \
		"$PKGDEST/usr/src/linux-7.1.5-saphira"
	# No /lib/modules/build link here, deliberately. That link belongs to
	# saphira-kernel, which owns the module directory; this package ships no
	# modules at all, and install_module_build_link correctly refuses a tree
	# with no /lib/modules/<rel> beneath it. A build-side consumer points KSRC
	# at /usr/src/linux-7.1.5-saphira directly, which is unambiguous and does
	# not pretend this package owns a module tree it does not have.
}
