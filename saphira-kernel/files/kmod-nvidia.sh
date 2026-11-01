#!/bin/sh
# kmod-nvidia.sh -- shared NVIDIA open-GPU-kernel-modules build logic for
# the per-kernel nvidia-open-<kver> recipes. Sourced from inside
# recipe_build()/recipe_install() (never at top level, so the metadata
# sandbox never executes it). Same worker-side contract as the other
# kmod helpers: a fresh tree prepared in-worker from declared inputs;
# the true KREL comes from `make kernelrelease` in that tree.

kmod_kver_full()
{
	# True kernel release, LOCALVERSION included: Makefile parsing
	# alone misses the suffix and misplaces suffixed-KREL modules.
	[ "$#" -eq 1 ] || return 1
	[ -f "$1/Makefile" ] || return 1
	make -s -C "$1" kernelrelease || return 1
}

kmod_srcball()
{
	if [ -f "$1" ]; then
		printf '%s  %s\n' "$2" "$1" | sha256sum -c - >/dev/null ||
			{ echo "kmod: vendored source failed verification: $1" >&2; return 1; }
		printf '%s\n' "$1"
	elif [ -n "${SOURCE_ARCHIVE-}" ] && [ -f "$SOURCE_ARCHIVE" ]; then
		printf '%s\n' "$SOURCE_ARCHIVE"
	else
		echo "kmod: no vendored source at $1 and no fetched SOURCE_ARCHIVE" >&2
		return 1
	fi
}


kmod_prepare_tree()
{
	# $1 = KVER_SHORT (tree directory name and reporting only). Ensures
	# a usable kernel tree at $SRC/linux-<short>, entirely under /build.
	# The kernel recipe is $KRECIPE (set by the calling kmod recipe,
	# e.g. KRECIPE=saphira-kernel-7.3): the .config seed, the source
	# tarball and the policy patches are read from that recipe's
	# files/ -- declared inputs, never /boot. A fresh tree is always
	# prepared in-worker; no staged /input tree is honoured (the
	# staging flow is retired and removed) and /usr/src is never
	# read or written. Either way no operator staging is required.
	#
	# modules_prepare depth: MODVERSIONS is off on every supported
	# line, so scripts + generated headers + sign-file suffice for
	# external Kbuild (no full kernel compile). The x86-64-v3 policy
	# patch is applied so module codegen matches the shipped kernel.
	# certs/ is not staged: prepare does not descend into it, and
	# signing uses /keys/module-signing.pem directly.
	_kshort=$1
	[ -n "${KRECIPE:?kmod: KRECIPE (kernel recipe directory) not set by caller}" ]
	_krecipedir="$RECIPE_DIR/../$KRECIPE"
	[ -d "$_krecipedir/files" ] ||
		{ echo "ERROR: kernel recipe files missing: $_krecipedir/files" >&2; return 1; }
	_kdir="$SRC/linux-$_kshort"
	# The .config seed is the kernel recipe's own vendored config (the
	# same file the kernel build copies before olddefconfig). Exactly
	# one config-* must exist; a second one means an ambiguous seed.
	_kconfig=$(echo "$_krecipedir"/files/config-*)
	case $_kconfig in
		*" "*) echo "ERROR: ambiguous config seed in $_krecipedir/files" >&2; return 1;;
	esac
	[ -f "$_kconfig" ] ||
		{ echo "ERROR: no vendored config in $_krecipedir/files" >&2; return 1; }
	rm -rf -- "$_kdir"
	mkdir -p "$_kdir"
	# Kernel tarball: the same verified bytes the kernel compiles. The
	# ball lives in the kernel recipe's files/ with its sha256 sidecar.
	# Per-extension match so the .sha256 sidecar never joins the glob.
	_kball=
	for _kext in tar.xz tar.gz tar.bz2; do
		for _kcand in "$_krecipedir"/files/linux-*."$_kext"; do
			[ -f "$_kcand" ] || continue
			[ -n "$_kball" ] &&
				{ echo "ERROR: ambiguous kernel tarball in $_krecipedir/files" >&2; return 1; }
			_kball=$_kcand
		done
	done
	unset _kext _kcand
	[ -f "$_kball" ] ||
		{ echo "ERROR: no vendored linux tarball in $_krecipedir/files" >&2; return 1; }
	[ -f "$_kball.sha256" ] ||
		{ echo "ERROR: kernel tarball has no verified sidecar: $_kball.sha256" >&2; return 1; }
	(cd "$(dirname "$_kball")" && sha256sum -c "$(basename "$_kball").sha256") ||
		{ echo "ERROR: kernel tarball failed its sha256 sidecar" >&2; return 1; }
	tar --no-same-owner -C "$_kdir" --strip-components=1 -xf "$_kball" ||
		{ echo "ERROR: kernel tarball extraction failed" >&2; return 1; }
	# Policy patches: the kernel recipe's own vendored bytes (same set
	# and order as the kernel build itself).
	[ -f "$_krecipedir/files/x86-64-v3.patch" ] ||
		{ echo "ERROR: policy patch missing: $_krecipedir/files/x86-64-v3.patch" >&2; return 1; }
	patch -d "$_kdir" -Np1 -i "$_krecipedir/files/x86-64-v3.patch" > "$SRC/kmod-v3.log" 2>&1 || return 1
	# Strict application (exact per-line context): fuzz or offset is
	# drift. The kernel and source builds gate the same bytes, so a
	# failure here means the copy regressed, never tolerance.
	if grep -qE 'fuzz|offset' "$SRC/kmod-v3.log"; then
			echo "ERROR: x86-64-v3.patch applied loosely (fuzz/offset): rebase it, do not ship drift" >&2
			grep -E 'fuzz|offset' "$SRC/kmod-v3.log" >&2
			return 1
		fi
	[ -f "$_krecipedir/files/cfg80211-regdb-freedom.patch" ] ||
		{ echo "ERROR: policy patch missing: $_krecipedir/files/cfg80211-regdb-freedom.patch" >&2; return 1; }
	patch -d "$_kdir" -Np1 -i "$_krecipedir/files/cfg80211-regdb-freedom.patch" > "$SRC/kmod-freedom.log" 2>&1 || return 1
	# Strict application, same rule as the v3 patch above.
	if grep -qE 'fuzz|offset' "$SRC/kmod-freedom.log"; then
		echo "ERROR: cfg80211-regdb-freedom.patch applied loosely (fuzz/offset): rebase it, do not ship drift" >&2
		grep -E 'fuzz|offset' "$SRC/kmod-freedom.log" >&2
		return 1
	fi
	cp "$_kconfig" "$_kdir/.config" ||
		{ echo "ERROR: cannot seed tree .config" >&2; return 1; }
	# Same merge the kernel build runs: the vendored config is the
	# pre-merge input, olddefconfig resolves it against the patched
	# Kconfig. Deterministic given the same tree and config.
	(cd "$_kdir" && make olddefconfig) ||
		{ echo "ERROR: kernel olddefconfig failed" >&2; return 1; }
	# Same proof gates the kernel build runs on the final .config.
	. "$_krecipedir/files/check-regdb-freedom.sh"
	check_regdb_freedom "$_kdir/.config" "$_kdir/net/wireless/Kconfig" ||
		{ echo "ERROR: regdb-freedom gate failed on prepared tree" >&2; return 1; }
	. "$_krecipedir/files/check-no-initramfs-builtins.sh"
	check_no_initramfs_builtins "$_kdir/.config" "$_kshort" ||
		{ echo "ERROR: no-initramfs-builtins gate failed on prepared tree" >&2; return 1; }
	(cd "$_kdir" && make modules_prepare -j${JOBS:-$(nproc)}) ||
		{ echo "ERROR: kernel modules_prepare failed" >&2; return 1; }
	# Full in-tree modules build, discarded afterwards: modpost writes
	# Module.symvers, which external Kbuild sanity-checks (NVIDIA
	# refuses a symvers-less tree). modules_prepare alone never
	# generates it. Same price the andrews contract pays; the old
	# shipped prepared tree carried symvers, so this restores that
	# contract instead of waiving the vendor check.
	(cd "$_kdir" && make modules -j${JOBS:-$(nproc)}) ||
		{ echo "ERROR: kernel modules build failed (Module.symvers)" >&2; return 1; }
	[ -s "$_kdir/Module.symvers" ] ||
		{ echo "ERROR: Module.symvers missing after modules build" >&2; return 1; }
	if [ ! -x "$_kdir/scripts/sign-file" ]; then
		(cd "$_kdir" && make scripts -j${JOBS:-$(nproc)}) ||
			{ echo "ERROR: kernel scripts build failed" >&2; return 1; }
	fi
	[ -x "$_kdir/scripts/sign-file" ] ||
		{ echo "ERROR: $_kdir/scripts/sign-file not built" >&2; return 1; }
}

kmod_nvidia_build()
{
	# $1 = KVER_SHORT, $2 = files/ tarball, $3 = sha256, $4 = files/ patch.
	_kshort=$1
	_kdir="$SRC/linux-$_kshort"
	# Signing key: fixed builder-exposed path (canonical host key, never
	# staged, never in /recipes). Absent key fails closed below.
	_key=/keys/module-signing.pem
	if [ ! -e "$_key" ]; then
		echo "ERROR: module signing key not exposed at $_key (builder key configuration?)" >&2
		return 1
	fi
	if [ ! -r "$_key" ]; then
		echo "ERROR: module signing key exposed but unreadable at $_key (UID ACL missing on the host key? builds must never go unsigned)" >&2
		return 1
	fi
	kmod_prepare_tree "$_kshort" ||
		{ echo "ERROR: no usable kernel tree for $_kshort (in-worker prepare failed)" >&2; return 1; }
	_kfull=$(kmod_kver_full "$_kdir") ||
		{ echo "ERROR: cannot derive kernel release from $_kdir/Makefile" >&2; return 1; }
	[ -x "$_kdir/scripts/sign-file" ] ||
		{ echo "ERROR: $_kdir/scripts/sign-file not built" >&2; return 1; }

	_nvball=$(kmod_srcball "$2" "$3") || return 1
	_ndir="$SRC/nvidia-$_kfull"
	rm -rf -- "$_ndir"
	mkdir -p "$_ndir"
	tar --no-same-owner -C "$_ndir" --strip-components=1 -xf "$_nvball"
	patch -d "$_ndir" -Np1 -i "$4" || return 1
	cd "$_ndir"

	make modules -j${JOBS:-$(nproc)} \
		SYSSRC="$_kdir" SYSOUT="$_kdir" \
		CC=gcc HOST_CC=gcc \
		IGNORE_CC_MISMATCH=1 \
		JOBS=${JOBS:-$(nproc)} || return 1

	for ko in kernel-open/*.ko; do
		"$_kdir/scripts/sign-file" sha256 "$_key" "$_key" "$ko" || return 1
	done
}

kmod_nvidia_install()
{
	# $1 = KVER_SHORT, $2 = module version (for the doc file).
	_kshort=$1
	_kdir="$SRC/linux-$_kshort"
	_kfull=$(kmod_kver_full "$_kdir") || return 1
	_ndir="$SRC/nvidia-$_kfull"
	cd "$_ndir" || return 1
	install -d "$PKGDEST/lib/modules/$_kfull/extra"
	for ko in kernel-open/nvidia.ko kernel-open/nvidia-modeset.ko \
		kernel-open/nvidia-drm.ko kernel-open/nvidia-uvm.ko; do
		[ -f "$ko" ] || { echo "ERROR: expected module missing: $ko" >&2; return 1; }
		install -m 0644 "$ko" "$PKGDEST/lib/modules/$_kfull/extra/" || return 1
	done
	# nouveau and nvidia-open bind the same hardware and must never
	# compete: installing the NVIDIA driver blacklists nouveau, the
	# standard driver-handover pattern. (Saphira kernels no longer
	# build nouveau at all; this covers foreign/older trees.)
	install -d "$PKGDEST/usr/lib/modprobe.d"
	printf 'blacklist nouveau\n' > "$PKGDEST/usr/lib/modprobe.d/nvidia-open.conf" || return 1
	install -d "$PKGDEST/usr/share/doc/nvidia-open-$_kshort"
	cat > "$PKGDEST/usr/share/doc/nvidia-open-$_kshort/README.Saphira" <<EOF
NVIDIA open kernel modules $2 for kernel $_kfull (host side only).

Load:
    depmod -a $_kfull
    modprobe nvidia
    modprobe nvidia_uvm
    modprobe nvidia_modeset
    modprobe nvidia_drm     (optional; DRM/KMS)

/dev/nvidia* nodes appear only when real NVIDIA hardware is present
(a VM without GPU passthrough loads the modules but creates no nodes).

GSP firmware comes from nvidia-open-firmware (strict version coupling).
No CUDA userspace ships here by policy: run CUDA inside a glibc
systemd-nspawn container with NVIDIA userland of the SAME release,
binding /dev/nvidia* into the container.

Modules are signed with the Saphira module signing key.
EOF
}
