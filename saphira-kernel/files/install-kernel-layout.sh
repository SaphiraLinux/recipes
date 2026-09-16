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
	[ "$#" -eq 4 ] || { kl_die "usage: check_module_layout ROOT KREL TREENAME EXPECTED_RELEASE"; return 1; }
	root=$1
	krel=$2
	tree=$3
	expected=$4
	link=$root/lib/modules/$krel/build
	[ -L "$link" ] || { kl_die "$link is not a symlink"; return 1; }
	target=$(readlink "$link")
	[ "$target" = "/usr/src/$tree" ] || { kl_die "$link -> $target (want /usr/src/$tree)"; return 1; }
	# Absolute installed targets resolve under the verified root, so
	# the same check validates a staged PKGDEST (root=$PKGDEST) and a
	# live system (root=/).
	case $target in
		/*) resolved=${root%/}$target ;;
		*) resolved=$(readlink -f "$link") ;;
	esac
	[ -d "$resolved" ] || { kl_die "$link resolves outside the tree: $resolved"; return 1; }
	[ ! -L "$root/lib/modules/$krel/source" ] || { kl_die "$root/lib/modules/$krel/source must not exist"; return 1; }
	got=$(make -s -C "$resolved" kernelrelease) || { kl_die "kernelrelease failed in $resolved"; return 1; }
	[ "$got" = "$expected" ] || { kl_die "kernelrelease $got (want $expected)"; return 1; }
	for artifact in Makefile .config Module.symvers \
		include/generated/autoconf.h arch/x86/include/generated/asm/unistd_64.h; do
		[ -f "$resolved/$artifact" ] || { kl_die "prepared-tree artifact missing: $artifact"; return 1; }
	done
	for tool in scripts/mod/modpost scripts/sign-file; do
		[ -x "$resolved/$tool" ] || { kl_die "prepared-tree tool missing or not built: $tool"; return 1; }
	done
	[ ! -e "$resolved/certs/module-signing.pem" ] || { kl_die "signing key leaked into $resolved/certs"; return 1; }
	leaks=$(find "$root" -lname '/build/*' 2>/dev/null)
	[ -z "$leaks" ] || { kl_die "installed symlinks point into /build:${leaks}"; return 1; }
	printf 'kernel-layout: %s OK (build -> %s, release %s)\n' "$link" "$target" "$got"
}
