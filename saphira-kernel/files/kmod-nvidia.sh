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
	printf '%s.%s.%s%s\n' "$_kv" "$_kp" "$_ks" "$_e"
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
	[ -f "$_kdir/Makefile" ] ||
		{ echo "ERROR: kernel build tree missing at $_kdir (staged /input?)" >&2; return 1; }
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
