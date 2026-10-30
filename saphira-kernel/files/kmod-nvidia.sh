#!/bin/sh
# kmod-nvidia.sh -- shared NVIDIA open-GPU-kernel-modules build logic for
# the per-kernel nvidia-open-<kver> recipes. Sourced from inside
# recipe_build()/recipe_install() (never at top level, so the metadata
# sandbox never executes it). Same staging contract as kmod-zfs.sh:
# the STAGED TREE couples the build; KVER_FULL derives from it.

kmod_kver_full()
{
	_kv=$(sed -n 's/^VERSION = //p' "$1/Makefile")
	_kp=$(sed -n 's/^PATCHLEVEL = //p' "$1/Makefile")
	_ks=$(sed -n 's/^SUBLEVEL = //p' "$1/Makefile")
	_ke=$(sed -n 's/^EXTRAVERSION = //p' "$1/Makefile")
	[ -n "$_kv" ] && [ -n "$_kp" ] && [ -n "$_ks" ] || return 1
	printf '%s.%s.%s%s\n' "$_kv" "$_kp" "$_ks" "$_ke"
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
	# $1 = KVER_SHORT. Ensures a usable kernel tree at
	# $SRC/linux-<short>, entirely under /build. A tree already
	# staged there (via buildpkg /input) is honoured only after
	# proving its .config matches the published kernel config;
	# otherwise a fresh tree is prepared from the vendored tarball
	# plus the published kernel's own built .config
	# (/boot/config-<short>-akadata, shipped by the installed
	# saphira-kernel-<short> package). Either way no operator
	# staging is required and /usr/src is never read or written.
	#
	# modules_prepare depth: MODVERSIONS is off on every supported
	# line, so scripts + generated headers + sign-file suffice for
	# external Kbuild (no full kernel compile). The x86-64-v3 policy
	# patch is applied so module codegen matches the shipped kernel.
	# certs/ is not staged: prepare does not descend into it, and
	# signing uses /keys/module-signing.pem directly.
	_kshort=$1
	_kdir="$SRC/linux-$_kshort"
	_kconfig="/boot/config-$_kshort-akadata"
	[ -f "$_kdir/Makefile" ] && _staged=1 || _staged=0
	if [ "$_staged" = "1" ]; then
		[ -f "$_kdir/.config" ] ||
			{ echo "ERROR: staged tree has no .config: $_kdir" >&2; return 1; }
		_tree_cfg=$(grep -vE '^[[:space:]]*(#|$)' "$_kdir/.config" | sed -e 's/[[:space:]]*$//' | LC_ALL=C sort)
		_pub_cfg=$(grep -vE '^[[:space:]]*(#|$)' "$_kconfig" | sed -e 's/[[:space:]]*$//' | LC_ALL=C sort)
		[ "$_tree_cfg" = "$_pub_cfg" ] ||
			{ echo "ERROR: staged tree .config disagrees with published $_kconfig (stale tree?)" >&2; return 1; }
	else
		[ -f "$_kconfig" ] ||
			{ echo "ERROR: published kernel config missing at $_kconfig (install saphira-kernel-$_kshort?)" >&2; return 1; }
		_krecipe="$RECIPE_DIR/../saphira-kernel-$_kshort"
		_kball="$RECIPE_DIR/../saphira-kernel-$_kshort/files/linux-$_kshort.tar.xz"
		[ -f "$_kball" ] || _kball="$RECIPE_DIR/../saphira-kernel-$_kshort/files/linux-$_kshort.tar.gz"
		[ -f "$_kball" ] ||
			{ echo "ERROR: no vendored linux-$_kshort tarball in saphira-kernel-$_kshort/files" >&2; return 1; }
		(cd "$(dirname "$_kball")" && sha256sum -c "$(basename "$_kball").sha256") ||
			{ echo "ERROR: kernel tarball failed its sha256 sidecar" >&2; return 1; }
		rm -rf -- "$_kdir"
		mkdir -p "$_kdir"
		tar --no-same-owner -C "$_kdir" --strip-components=1 -xf "$_kball" ||
			{ echo "ERROR: kernel tarball extraction failed" >&2; return 1; }
		[ -f "$_krecipe/files/x86-64-v3.patch" ] ||
			{ echo "ERROR: sibling policy patch missing for $_kshort" >&2; return 1; }
		patch -d "$_kdir" -Np1 -i "$_krecipe/files/x86-64-v3.patch" || return 1
		cp "$_kconfig" "$_kdir/.config" ||
			{ echo "ERROR: cannot seed tree .config" >&2; return 1; }
		(cd "$_kdir" && make modules_prepare -j${JOBS:-$(nproc)}) ||
			{ echo "ERROR: kernel modules_prepare failed" >&2; return 1; }
	fi
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
		{ echo "ERROR: no usable kernel tree for $_kshort (self-prepare failed and none staged)" >&2; return 1; }
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
