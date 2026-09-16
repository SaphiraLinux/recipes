#!/bin/sh
# kmod-drbd.sh -- shared DRBD 9 out-of-tree module build logic for the
# per-kernel saphira-drbd9-<kver> recipes. Sourced from inside
# recipe_build()/recipe_install() (never at top level, so the metadata
# sandbox never executes it). Same staging contract as kmod-zfs.sh.
#
# SPAAS (spatch-as-a-service) stays at its default: the sandbox has
# network, and without it the build degrades to local spatch (not
# packaged) or an empty compat patch and fails visibly at compile
# time if the kernel actually needs patching - never silently wrong.

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

kmod_drbd_build()
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

	_dball=$(kmod_srcball "$2" "$3") || return 1
	_ddir="$SRC/drbd-$_kfull"
	rm -rf -- "$_ddir"
	mkdir -p "$_ddir"
	tar --no-same-owner -C "$_ddir" --strip-components=1 -xf "$_dball"
	cd "$_ddir"

	make KDIR="$_kdir" KVER="$_kfull" module -j${JOBS:-$(nproc)} || return 1

	for ko in $(find . -name '*.ko' -not -name '.*'); do
		"$_kdir/scripts/sign-file" sha256 "$_key" "$_key" "$ko" || return 1
	done
}

kmod_drbd_install()
{
	# $1 = KVER_SHORT.
	_kshort=$1
	_kdir="$SRC/linux-$_kshort"
	_kfull=$(kmod_kver_full "$_kdir") || return 1
	_ddir="$SRC/drbd-$_kfull"
	install -d "$PKGDEST/lib/modules/$_kfull/extra"
	for ko in $(find "$_ddir" -name '*.ko' -not -name '.*'); do
		install -m 644 "$ko" "$PKGDEST/lib/modules/$_kfull/extra/" || return 1
	done
}
