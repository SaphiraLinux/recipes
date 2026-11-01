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
		patch -d "$_kdir" -Np1 -i "$_krecipe/files/x86-64-v3.patch" > "$SRC/kmod-v3.log" 2>&1 || return 1
		# Strict application (exact per-line context): fuzz or offset is
		# drift. The kernel and source builds gate the same bytes, so a
		# failure here means the copy regressed, never tolerance.
		if grep -qE 'fuzz|offset' "$SRC/kmod-v3.log"; then
			echo "ERROR: x86-64-v3.patch applied loosely (fuzz/offset): rebase it, do not ship drift" >&2
			grep -E 'fuzz|offset' "$SRC/kmod-v3.log" >&2
			return 1
		fi
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
	kmod_prepare_tree "$_kshort" ||
		{ echo "ERROR: no usable kernel tree for $_kshort (self-prepare failed and none staged)" >&2; return 1; }
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
	install -d "$PKGDEST/usr/share/doc/saphira-drbd9-$_kshort"
	cat > "$PKGDEST/usr/share/doc/saphira-drbd9-$_kshort/README.Saphira" <<EOF
DRBD 9 out-of-tree kernel modules for kernel $_kfull (host side only).

Load:
    depmod -a $_kfull
    modprobe drbd

Management (drbdadm, drbdsetup, drbdmeta) comes from drbd-utils;
event-driven failover from drbd-reactor (optional).

Modules are signed with the Saphira module signing key.
EOF
	# Declared maintainer hooks: refresh the module index for THIS release
	# after the module tree changes. Same policy as kmod-zfs.sh: without
	# them the package installs cleanly and installs modules modprobe
	# cannot find, because modules.dep was generated when the KERNEL was
	# installed and knows nothing about extra/.
	#
	# The release is passed EXPLICITLY and is this package's own KVER, so
	# the hook can never reindex a different kernel than the one whose
	# tree it just changed. Bare `depmod -a' and `uname -r' are both
	# wrong: the installed package may target a kernel other than the
	# running one. post-deinstall is included because removal changes the
	# tree too. A missing module tree is a legitimate no-op; a depmod
	# that runs and fails is not swallowed.
	install -d -m 0755 "$PKGDEST/usr/share/saphira/hooks.d/$pkgname"
	for _hook_kind in post-install post-upgrade post-deinstall; do
		cat > "$PKGDEST/usr/share/saphira/hooks.d/$pkgname/$_hook_kind" <<EOF
#!/bin/sh
# Generated by saphira-kernel/files/kmod-drbd.sh for $pkgname.
# Refresh the module index for $_kfull, the release this package ships.
# Absolute path, and it is /usr/sbin/depmod because that is where the
# kmod recipe installs it (see kmod-zfs.sh for the full rationale).
# apk passes the version as \$1; it is deliberately unused.
[ -d /lib/modules/$_kfull ] && /usr/sbin/depmod $_kfull
exit 0
EOF
		chmod 0755 "$PKGDEST/usr/share/saphira/hooks.d/$pkgname/$_hook_kind"
	done
}
