pkgname=saphira-kernel-source-7.3-rc1
pkgver=1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Saphira kernel 7.3-rc1 external-module build tree (Kbuild: Makefile, Module.symvers, generated headers, modpost, sign-file)'
license='GPL-2.0-only'
origin=saphira-kernel-source-7.3-rc1
repo=saphira
url=https://saphira.vm2.uk/

# BUILD-SIDE ONLY. This package exists so an out-of-tree module (saphira-zfs-7.3-rc1,
# nvidia-open-7.3-rc1, saphira-drbd9-7.3-rc1) can be compiled against THIS kernel's
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
# Renamed from saphira-kernel-devel-7.3-rc1 (same payload contract;
# identity follows the versioned kernel family, origin tracks identity).
# install_prepared_tree already removes build intermediates (*.o, *.cmd, *.ko,
# built-in.a, vmlinux, System.map, .tmp_vmlinux*), the module signing PRIVATE
# key, Documentation, and the standalone userspace bulk of tools/.

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
# The module signing key is build-time only and is exposed read-only by the
# builder at the fixed path below. It is never staged, never copied into
# /recipes, and install_prepared_tree removes it from the payload.
SAPHIRA_MODULE_KEY_DEFAULT=/keys/module-signing.pem

recipe_build()
{
	export TAR_OPTIONS=--no-same-owner
	# Builder-exposed read-only module signing key, same fixed path
	# saphira-kernel uses. Absent key must fail closed, never sign nothing.
	KEY=/keys/module-signing.pem
	[ -r "$KEY" ] || {
		echo "ERROR: module signing key not readable at $KEY" >&2
		return 1
	}

	# 7.3-rc1 is a .tar.gz (torvalds cgit snapshot); the rest are .tar.xz.
	# Same fallback saphira-kernel uses, rather than hardcoding one spelling.
	KBALL="$RECIPE_DIR/../saphira-kernel-7.3-rc1/files/linux-7.3-rc1.tar.xz"
	[ -f "$KBALL" ] || KBALL="$RECIPE_DIR/../saphira-kernel-7.3-rc1/files/linux-7.3-rc1.tar.gz"
	[ -f "$KBALL" ] || { echo "ERROR: no vendored 7.3-rc1 kernel archive (.tar.xz or .tar.gz)" >&2; return 1; }
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
	kernel_sha=$(grep -m1 "^sha256=" \
		"$RECIPE_DIR/../saphira-kernel-7.3-rc1/recipe.sh" | cut -d= -f2)
	side_sha=$(awk 'NR==1{print $1}' "$KBALL.sha256")
	[ -n "$kernel_sha" ] && [ "$kernel_sha" = "$side_sha" ] || {
		echo "ERROR: source tree archive does not match saphira-kernel-7.3-rc1 pin" >&2
		echo "  saphira-kernel: ${kernel_sha:-<none>}" >&2
		echo "  sidecar:        ${side_sha:-<none>}" >&2
		return 1
	}

	mkdir -p "$SRC/linux-7.3-rc1"
	tar --no-same-owner -C "$SRC/linux-7.3-rc1" --strip-components=1 -xf "$KBALL"
	cd "$SRC/linux-7.3-rc1"

	patch -Np1 -i "$RECIPE_DIR/../saphira-kernel-7.3-rc1/files/x86-64-v3.patch"
	# The SAME canonical config file saphira-kernel builds from. Shared by
	# path, not copied, so the two cannot drift.
	cp "$RECIPE_DIR/../saphira-kernel-7.3-rc1/files/config-7.3-rc1-akadata" "$SRC/linux-7.3-rc1/.config"

	mkdir -p "$SRC/linux-7.3-rc1/certs/regdb"
	cp "$RECIPE_DIR/../saphira-kernel-7.3-rc1/files/saphira-regdb.x509" \
	   "$SRC/linux-7.3-rc1/certs/regdb/saphira-regdb.x509"
	cp "$KEY" "$SRC/linux-7.3-rc1/certs/module-signing.pem"
	chmod 600 "$SRC/linux-7.3-rc1/certs/module-signing.pem"

	make olddefconfig
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	. "$RECIPE_DIR/../saphira-kernel-7.3-rc1/files/install-kernel-layout.sh"
	KREL=$(kernel_layout_release "$SRC/linux-7.3-rc1")
	install_prepared_tree "$SRC/linux-7.3-rc1" "$PKGDEST/usr/src/linux-7.3-rc1-saphira"
	# No /lib/modules/build link here, deliberately. That link belongs to
	# saphira-kernel, which owns the module directory; this package ships no
	# modules at all, and install_module_build_link correctly refuses a tree
	# with no /lib/modules/<rel> beneath it. A build-side consumer points KSRC
	# at /usr/src/linux-7.3-rc1-saphira directly, which is unambiguous and does
	# not pretend this package owns a module tree it does not have.
}
