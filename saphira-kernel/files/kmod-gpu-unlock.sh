#!/bin/sh
# kmod-gpu-unlock.sh -- shared gpu-unlock out-of-tree module build logic
# for the per-kernel gpu-unlock-<kver> recipes. Sourced from inside
# recipe_build()/recipe_install() (never at top level, so the metadata
# sandbox never executes it). Same staging contract as kmod-drbd.sh:
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
	elif [ -n "${SOURCE_ARCHIVE-}" ] && [ -f "${SOURCE_ARCHIVE-}" ]; then
		printf '%s\n' "$SOURCE_ARCHIVE"
	else
		echo "kmod: no vendored source at $1 and no fetched SOURCE_ARCHIVE" >&2
		return 1
	fi
}

# Firmware manifest: the exact blob set gpu_unlock.ko requests
# (modinfo -F firmware), extracted from the NVIDIA installer named in
# the recipe. Missing or extra blobs fail the install, never ship
# a half firmware tree the module would half-load.
kmod_gpu_unlock_firmware_files()
{
	printf '%s\n' \
		booter_load_ad102.bin booter_load_ga100.bin \
		booter_load_ga102.bin booter_load_tu102.bin \
		falcon_loader.bin \
		gsp_boot_ad102.bin gsp_boot_desc_ad102.bin \
		gsp_boot_ga100.bin gsp_boot_desc_ga100.bin \
		gsp_boot_ga102.bin gsp_boot_desc_ga102.bin \
		gsp_boot_tu102.bin gsp_boot_desc_tu102.bin \
		gsp_ga10x.bin gsp_tu10x.bin sec2_bl_tu102.bin
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

kmod_gpu_unlock_build()
{
	# $1 = KVER_SHORT, $2 = files/ source tarball, $3 = sha256.
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

	_gball=$(kmod_srcball "$2" "$3") || return 1
	_gdir="$SRC/gpu-unlock-$_kfull"
	rm -rf -- "$_gdir"
	mkdir -p "$_gdir"
	tar --no-same-owner -C "$_gdir" --strip-components=1 -xf "$_gball"
	_mdir="$_gdir/kernel/gpu_unlock"
	[ -f "$_mdir/Kbuild" ] ||
		{ echo "ERROR: no Kbuild in $_mdir (upstream layout drift?)" >&2; return 1; }

	make -C "$_kdir" M="$_mdir" modules -j${JOBS:-$(nproc)} || return 1
	[ -f "$_mdir/gpu_unlock.ko" ] ||
		{ echo "ERROR: gpu_unlock.ko missing after Kbuild" >&2; return 1; }
	"$_kdir/scripts/sign-file" sha256 "$_key" "$_key" "$_mdir/gpu_unlock.ko" || return 1
}

kmod_gpu_unlock_install()
{
	# $1 = KVER_SHORT, $2 = files/ firmware tarball, $3 = firmware sha256.
	_kshort=$1
	_kdir="$SRC/linux-$_kshort"
	_kfull=$(kmod_kver_full "$_kdir") || return 1
	_gdir="$SRC/gpu-unlock-$_kfull"
	_mdir="$_gdir/kernel/gpu_unlock"
	[ -f "$_mdir/gpu_unlock.ko" ] ||
		{ echo "ERROR: gpu_unlock.ko missing (build ran?)" >&2; return 1; }
	install -d "$PKGDEST/lib/modules/$_kfull/extra"
	install -m 644 "$_mdir/gpu_unlock.ko" "$PKGDEST/lib/modules/$_kfull/extra/" || return 1

	# Firmware: vendored pre-extracted set (offline builder cannot run
	# the NVIDIA installer). Verified against the recipe pin, unpacked
	# under $SRC, installed read-only. No extraction tooling ships.
	_fball=$(kmod_srcball "$2" "$3") || return 1
	_fdir="$SRC/gpu-unlock-firmware"
	rm -rf -- "$_fdir"
	mkdir -p "$_fdir"
	tar --no-same-owner -C "$_fdir" -xf "$_fball"
	for _fw in $(kmod_gpu_unlock_firmware_files); do
		[ -f "$_fdir/$_fw" ] ||
			{ echo "ERROR: firmware blob missing from vendored set: $_fw" >&2; return 1; }
	done
	if [ "$(ls "$_fdir" | wc -l)" -ne 16 ]; then
		echo "ERROR: vendored firmware set has stray files (want exactly the 16 requested blobs)" >&2
		ls "$_fdir" >&2
		return 1
	fi
	install -d "$PKGDEST/lib/firmware/gpu-unlock/610.43.03"
	for _fw in $(kmod_gpu_unlock_firmware_files); do
		install -m 644 "$_fdir/$_fw" "$PKGDEST/lib/firmware/gpu-unlock/610.43.03/" || return 1
	done

	# Upstream licensing, preserved byte-for-byte: module sources are
	# GPL-2.0-only, firmware blobs carry the NVIDIA license.
	for _lic in GPL-2.0.txt CMP40HX-MIT.txt NVIDIA-MIT.txt; do
		[ -f "$_gdir/licenses/$_lic" ] ||
			{ echo "ERROR: upstream license missing from source tree: $_lic" >&2; return 1; }
	done
	install -d "$PKGDEST/usr/share/licenses/gpu-unlock-$_kshort"
	for _lic in GPL-2.0.txt CMP40HX-MIT.txt NVIDIA-MIT.txt; do
		install -m 644 "$_gdir/licenses/$_lic" "$PKGDEST/usr/share/licenses/gpu-unlock-$_kshort/" || return 1
	done
	# Activation is operator opt-in ONLY. This file documents the module
	# parameters and carries no directives, so installing the package
	# changes nothing about what loads at boot.
	install -d "$PKGDEST/usr/lib/modprobe.d"
	cat > "$PKGDEST/usr/lib/modprobe.d/gpu-unlock.conf" <<EOF
# gpu-unlock: out-of-tree tensor-throughput unlock (NOT an overclock,
# VRAM expansion, or vGPU implementation). Inert unless loaded with
# targets=; see /usr/share/doc/gpu-unlock-$_kshort/README.Saphira.
#
# Example (operator opt-in, /etc/modprobe.d/gpu-unlock.conf):
# options gpu_unlock targets=all
EOF
	install -d "$PKGDEST/usr/share/doc/gpu-unlock-$_kshort"
	cat > "$PKGDEST/usr/share/doc/gpu-unlock-$_kshort/README.Saphira" <<EOF
gpu-unlock 2.0.0 out-of-tree kernel module for kernel $_kfull.

What it is: modifies NVIDIA GPU initialisation to unlock otherwise
restricted hardware tensor-core throughput on supported GPUs
(Ampere and friends; proven on RTX 3060 GA106: sustained BF16
26.5 -> ~47.5 TFLOPS, similar FP16/TF32, FP32 unchanged). NOT an
overclock, VRAM expansion, or vGPU implementation.

Activation (ALL operator steps, none automatic):
  1. Append gpu_unlock.targets=all to the kernel command line
     (GRUB kernel line; the parameter applies whenever the module
     loads and cannot be reliably toggled at runtime).
  2. Load gpu_unlock BEFORE the NVIDIA driver binds, e.g. an
     operator-owned /etc/modules-load.d/gpu_unlock.conf containing
     one line: gpu_unlock
     (openrc loads modules-load.d before drivers bind; verify with
     dmesg on first boot).
  3. Reboot. Verify: dmesg shows gpu_unlock initialising ahead of
     nvidia, and tensor workloads report unlocked throughput.

Without targets= the module loads inert and changes nothing.
resume=1 (default) re-applies after suspend-resume.

Firmware: pre-extracted NVIDIA 610.43.03 GSP set under
/lib/firmware/gpu-unlock/610.43.03/ (16 blobs, NVIDIA license in
/usr/share/licenses/gpu-unlock-$_kshort/NVIDIA-MIT.txt). Proven
matrix: gpu-unlock 2.0.0 + this firmware set + NVIDIA driver
610.57.04 (nvidia-open-$_kshort); do not mix other releases.

Reversal: apk del gpu-unlock-$_kshort, remove the kernel parameter
and any operator-owned load entry, reboot. The depmod index is
refreshed on install, upgrade and removal.

Modules are signed with the Saphira module signing key.
EOF
	# Declared maintainer hooks: refresh the module index for THIS release
	# after the module tree changes (same policy as kmod-drbd.sh: the
	# index belongs to the kernel package, so a new module is
	# unloadable without this). Explicit release, never bare depmod.
	install -d -m 0755 "$PKGDEST/usr/share/saphira/hooks.d/$pkgname"
	for _hook_kind in post-install post-upgrade post-deinstall; do
		cat > "$PKGDEST/usr/share/saphira/hooks.d/$pkgname/$_hook_kind" <<EOF
#!/bin/sh
# Generated for $pkgname: refresh the module index for $_kfull.
# apk passes the version as \$1; it is deliberately unused.
[ -d /lib/modules/$_kfull ] && /usr/sbin/depmod $_kfull
exit 0
EOF
		chmod 0755 "$PKGDEST/usr/share/saphira/hooks.d/$pkgname/$_hook_kind"
	done
}
