#!/bin/sh
# kmod-zfs.sh -- shared OpenZFS out-of-tree module build logic for the
# per-kernel saphira-zfs-<kver> recipes. Sourced from inside
# recipe_build()/recipe_install() (never at top level, so the metadata
# sandbox never executes it).
#
# The kernel version coupling is the STAGED TREE ($SRC/linux-<short>
# from /input via stage-kmod-input.sh), not the saphira-kernel-headers
# pin (host UAPI only). KVER_FULL (module install path) derives from
# the tree's own Makefile, so release candidates map correctly
# (7.3-rc1 tree -> /lib/modules/7.3.0-rc1/extra).

kmod_kver_full()
{
	# Prints KERNELRELEASE (VERSION.PATCHLEVEL.SUBLEVEL+EXTRAVERSION)
	# for the staged tree in $1. Fails closed on unparseable Makefiles.
	_kv=$(sed -n 's/^VERSION = //p' "$1/Makefile")
	_kp=$(sed -n 's/^PATCHLEVEL = //p' "$1/Makefile")
	_ks=$(sed -n 's/^SUBLEVEL = //p' "$1/Makefile")
	_ke=$(sed -n 's/^EXTRAVERSION = //p' "$1/Makefile")
	[ -n "$_kv" ] && [ -n "$_kp" ] && [ -n "$_ks" ] || return 1
	printf '%s.%s.%s%s\n' "$_kv" "$_kp" "$_ks" "$_e"
}

kmod_srcball()
{
	# $1 = files/ path, $2 = sha256. Verifies the vendored copy, else
	# falls back to the builder-fetched SOURCE_ARCHIVE. Prints the path.
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

kmod_zfs_build()
{
	# $1 = KVER_SHORT, $2 = files/ tarball, $3 = sha256.
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

	_zball=$(kmod_srcball "$2" "$3") || return 1
	_zdir="$SRC/zfs-$_kfull"
	rm -rf -- "$_zdir"
	mkdir -p "$_zdir"
	tar --no-same-owner -C "$_zdir" --strip-components=1 -xf "$_zball"
	cd "$_zdir"

	./configure --prefix=/usr --sysconfdir=/etc \
		--with-linux="$_kdir" --with-linux-obj="$_kdir" \
		--with-config=all || return 1
	make -j${JOBS:-$(nproc)} || return 1

	for ko in module/*.ko; do
		"$_kdir/scripts/sign-file" sha256 "$_key" "$_key" "$ko" || return 1
	done
}

kmod_zfs_install()
{
	# $1 = KVER_SHORT.
	_kshort=$1
	_kdir="$SRC/linux-$_kshort"
	_kfull=$(kmod_kver_full "$_kdir") || return 1
	_zdir="$SRC/zfs-$_kfull"
	install -d "$PKGDEST/lib/modules/$_kfull/extra"
	install -m 644 "$_zdir/module/zfs.ko" "$_zdir/module/spl.ko" \
		"$PKGDEST/lib/modules/$_kfull/extra/" || return 1
	install -d "$PKGDEST/usr/share/doc/saphira-zfs-$_kshort"
	cat > "$PKGDEST/usr/share/doc/saphira-zfs-$_kshort/README.Saphira" <<EOF
OpenZFS kernel modules for kernel $_kfull (host side only).

Load:
    depmod -a $_kfull
    modprobe zfs

Userspace (zpool, zfs, libraries) comes from saphira-zfs-userspace.
Pool compatibility: mounts existing 2.4.1 / 2.4.3 pools; do NOT zpool
upgrade.

Modules are signed with the Saphira module signing key.
EOF
}
