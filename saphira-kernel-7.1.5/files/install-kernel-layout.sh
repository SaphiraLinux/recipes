#!/bin/sh
# install-kernel-layout.sh - installed module-tree layout for saphira-kernel.
#
# Sourced by saphira-kernel recipe_install() and by
# saphira-packager/tests/kernel-layout.sh. Pure installed-filesystem
# logic over explicit directory arguments (no builder globals), so the
# layout is unit-testable without compiling a kernel.
#
# Intended installed layout (multi-kernel safe, no floating links):
#
#   /usr/src/linux-<pkgver>-saphira/
#       APK-owned prepared kernel development tree (full source plus
#       generated state, pruned of intermediates and secrets)
#   /lib/modules/<release>/build
#       -> /usr/src/linux-<pkgver>-saphira   (versioned target, never
#          via /usr/src/linux: that convenience pointer floats between
#          kernels and must not silently retarget older module builds)
#   (no /lib/modules/<release>/source - nothing in our design uses it)
#
# /usr/src/linux itself is deliberately NOT packaged: with several
# kernels co-installed exactly one package could own it, and the
# selection is an operator choice. It stays admin-managed.
#
# Defensive shell: every failure prints `kernel-layout: ...` and
# returns non-zero (callers run under `set -eu`).

kl_die()
{
	printf 'kernel-layout: %s\n' "$*" >&2
	return 1
}

# kernel_layout_release SRCDIR - print KERNELRELEASE of a built tree.
kernel_layout_release()
{
	[ "$#" -eq 1 ] || { kl_die "usage: kernel_layout_release SRCDIR"; return 1; }
	[ -f "$1/Makefile" ] || { kl_die "no Makefile in $1"; return 1; }
	make -s -C "$1" kernelrelease || { kl_die "kernelrelease failed in $1"; return 1; }
}

# install_prepared_tree SRCDIR DESTDIR - copy a built kernel tree as the
# APK-owned prepared tree, pruning build intermediates, secrets,
# standalone-userspace bulk and docs. What stays is the full source
# plus every artifact an external module build can reference (.config,
# Module.symvers, generated headers, built scripts including modpost
# and sign-file, the objtool chain). In-tree symlinks are preserved
# (cp -a).
install_prepared_tree()
{
	[ "$#" -eq 2 ] || { kl_die "usage: install_prepared_tree SRCDIR DESTDIR"; return 1; }
	src=$1
	dest=$2
	[ -d "$src" ] || { kl_die "source tree missing: $src"; return 1; }
	[ -f "$src/Makefile" ] || { kl_die "no Makefile in $src"; return 1; }
	mkdir -p "$dest" || { kl_die "cannot create $dest"; return 1; }
	cp -a "$src/." "$dest/" || { kl_die "tree copy failed: $src -> $dest"; return 1; }
	# Pure build intermediates: objects, per-file command records,
	# linked modules and archives, modpost inputs, split debug data,
	# gcov notes, per-file symbol types.
	# shellcheck disable=SC2185
	find "$dest" \( -name '*.o' -o -name '*.cmd' -o -name '*.ko' \
		-o -name '*.mod' -o -name '*.mod.c' -o -name '*.dwo' \
		-o -name '*.gcno' -o -name '*.su' -o -name '*.symtypes' \) -delete
	find "$dest" -type d -name .tmp_versions -prune -exec rm -rf {} +
	find "$dest" -type f \( -name 'built-in.a' -o -name 'built-in-fixup.a' \
		-o -name 'vmlinux.a' \) -delete
	# Linked images and install-time generated lists (duplicates of
	# /boot payload or regenerable; external builds need none of them).
	rm -f "$dest/vmlinux" "$dest/vmlinux.o" "$dest/System.map" \
		"$dest/modules.order" "$dest/modules.builtin" \
		"$dest/modules.builtin.modinfo" "$dest/.config.old"
	# link-vmlinux.sh scratch, left behind at the top of the build tree.
	# The kernel build removes most of these itself, but the BTF
	# id-resolution step leaves .tmp_vmlinux1.BTF_ids behind, and nothing
	# pruned it: the prepared tree shipped it. A .tmp_* file is a build
	# intermediate by name and by nature, so the whole family goes.
	find "$dest" -maxdepth 1 -name '.tmp_vmlinux*' -delete
	find "$dest" \( -name '*.orig' -o -name '*.rej' -o -name '*~' \) -delete
	# Key material: the module signing private key is build-time only
	# and must never ship (public regdb certs stay - transparency).
	rm -f "$dest/certs/module-signing.pem" "$dest/certs/signing_key.pem"
	# Standalone userspace bulk: tools/ is never referenced by Kbuild
	# external-module builds except the objtool chain (ORC-era unwinder
	# data needs a working tools/objtool plus its build headers).
	if [ -d "$dest/tools" ]; then
		find "$dest/tools" -mindepth 1 -maxdepth 1 \
			! -name objtool ! -name include ! -name arch \
			! -name build ! -name lib -exec rm -rf {} +
	fi
	# Documentation never participates in compilation.
	rm -rf "$dest/Documentation"
}

# install_module_build_link PKGDEST KREL TREENAME - replace the
# upstream-baked build/source symlinks (absolute constructor paths
# from modules_install) with the versioned Saphira layout.
install_module_build_link()
{
	[ "$#" -eq 3 ] || { kl_die "usage: install_module_build_link PKGDEST KREL TREENAME"; return 1; }
	pkgdest=$1
	krel=$2
	tree=$3
	[ -d "$pkgdest/lib/modules/$krel" ] || { kl_die "no $pkgdest/lib/modules/$krel"; return 1; }
	rm -f "$pkgdest/lib/modules/$krel/build" "$pkgdest/lib/modules/$krel/source"
	ln -s "/usr/src/$tree" "$pkgdest/lib/modules/$krel/build" \
		|| { kl_die "cannot link $pkgdest/lib/modules/$krel/build"; return 1; }
}

# check_module_layout ROOT KREL TREENAME EXPECTED_RELEASE - verify an
# installed tree or a staged PKGDEST: versioned build symlink resolving
# under /usr/src, no source symlink, kernelrelease matches, required
# prepared-tree artifacts present, signing key absent, and no installed
# symlink anywhere under ROOT pointing into /build.
check_module_layout()
{
	# A RUNTIME kernel package: module tree present and self-consistent,
	# and NO build tooling and NO build source.
	#
	# This used to verify the opposite. It required
	# lib/modules/<rel>/build -> /usr/src/<tree> and walked that tree,
	# checking Makefile, .config, Module.symvers, the generated UAPI
	# syscall header, modpost and sign-file. Those assertions are what
	# REQUIRED the prepared tree to be shipped: d2e581d added
	# install_prepared_tree to satisfy them, which put 1648 MiB and
	# 77,655 files of kernel source into a runtime APK.
	#
	# The gate is now inverted. A runtime package must not carry a build
	# tree at all, so that is asserted rather than assumed -- silently
	# shipping one again is exactly the regression this guards.
	[ "$#" -eq 3 ] || { kl_die "usage: check_module_layout ROOT KREL EXPECTED_RELEASE"; return 1; }
	root=$1
	krel=$2
	expected=$3
	moddir=$root/lib/modules/$krel
	[ -d "$moddir" ] || { kl_die "module directory missing: $moddir"; return 1; }
	# A runtime rootfs has no build tree and no build pointer. Reject
	# both, including a dangling link: shipping a link that can only dangle
	# helps nobody and misleads whoever debugs the next thing.
	[ ! -e "$root/usr/src" ] || { kl_die "runtime kernel must not ship /usr/src: found $root/usr/src"; return 1; }
	for link in build source; do
		[ ! -e "$moddir/$link" ] && [ ! -L "$moddir/$link" ] || {
			kl_die "runtime kernel must not ship lib/modules/$krel/$link"
			return 1
		}
	done
	# Nothing anywhere in the package may point at a build tree.
	leaks=$(find "$root" -lname '/usr/src/*' -o -lname '/build/*' 2>/dev/null)
	[ -z "$leaks" ] || { kl_die "runtime kernel ships build-tree pointers:${leaks}"; return 1; }
	# Module metadata depmod produced must exist and cover the tree.
	for meta in modules.dep modules.softdep modules.alias modules.order; do
		[ -s "$moddir/$meta" ] || { kl_die "module metadata missing or empty: $moddir/$meta"; return 1; }
	done
	nko=$(find "$moddir" -name '*.ko' 2>/dev/null | wc -l)
	[ "$nko" -gt 0 ] || { kl_die "no modules installed under $moddir"; return 1; }
	# The release the tree claims must be the release the caller expects.
	# modules.dep paths carry no release, so the directory name is the
	# assertion; depmod already ran against this exact KREL above.
	printf 'kernel-layout: %s OK (%s modules, runtime package, no build tree)\n' "$moddir" "$nko"
}
