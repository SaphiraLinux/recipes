#!/bin/sh
# kmod-zfs.sh -- shared OpenZFS out-of-tree module build logic for the
# per-kernel saphira-zfs-<kver> recipes. Sourced from inside
# recipe_build()/recipe_install() (never at top level, so the metadata
# sandbox never executes it).
#
# The kernel version coupling is a PREPARED TREE at $SRC/linux-<short>,
# not the UAPI package (saphira-linux-uapi-headers, host UAPI only).
# The tree is prepared here, from the sibling saphira-kernel-<short>
# recipe's vendored tarball + pinned config (verified, olddefconfig,
# modules_prepare) — all under /build, so plain `buildpkg <kmod>`
# works with no /input staging and /usr/src is never involved. A tree
# already staged at $SRC/linux-<short> (via /input) is still honoured
# when present, so the old path keeps working. KVER_FULL (module
# install path) derives from the tree's own Makefile, so release
# candidates map correctly (7.3-rc1 tree -> /lib/modules/7.3.0-rc1/extra).

kmod_kver_full()
{
	# Prints KERNELRELEASE (VERSION.PATCHLEVEL.SUBLEVEL+EXTRAVERSION+
	# CONFIG_LOCALVERSION) for the staged tree in $1. Fails closed on
	# unparseable Makefiles. The LOCALVERSION suffix matters: a tree
	# built for 7.2.9-ccram must yield 7.2.9-ccram, not 7.2.9, or
	# modules land under a release modprobe never looks at. Trees
	# without a LOCALVERSION line behave exactly as before.
	_kv=$(sed -n 's/^VERSION = //p' "$1/Makefile")
	_kp=$(sed -n 's/^PATCHLEVEL = //p' "$1/Makefile")
	_ks=$(sed -n 's/^SUBLEVEL = //p' "$1/Makefile")
	_ke=$(sed -n 's/^EXTRAVERSION = //p' "$1/Makefile")
	[ -n "$_kv" ] && [ -n "$_kp" ] && [ -n "$_ks" ] || return 1
	_kl=$(sed -n 's/^CONFIG_LOCALVERSION="//p' "$1/.config" 2>/dev/null | tr -d '"' || true)
	printf '%s.%s.%s%s%s\n' "$_kv" "$_kp" "$_ks" "$_ke" "$_kl"
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

kmod_prepare_tree()
{
	# $1 = KVER_SHORT. Ensures a usable kernel tree at
	# $SRC/linux-<short>, entirely under /build — the proven 7.3
	# pattern, shared. A tree already staged there (via /input) is
	# honoured only after proving its config; otherwise a fresh tree
	# is prepared from the vendored tarball plus the published
	# kernel's own built .config. Either way the tree this builds
	# against is exact, and no host state decides it. /usr/src is
	# never read and never written.
	#
	# Full kernel build, not just scripts+prepare: ZFS configure needs
	# Module.symvers (only modpost generates it), and modpost needs
	# vmlinux (proven by mce-inject.ko failing without it). This is
	# the price of self-staging: ~one full kernel compile per kmod
	# package, all under /build (and ccache now actually hits there).
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
			{ echo "ERROR: published kernel config missing at $_kconfig (saphira-kernel-$_kshort depends broken?)" >&2; return 1; }
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
		cp "$_kconfig" "$_kdir/.config" ||
			{ echo "ERROR: cannot seed tree .config" >&2; return 1; }
		# Build-time key material, mirroring the kernel recipe:
		# the .config names certs/module-signing.pem and the
		# regdb anchor, and the certs build fails without them.
		# Same bytes, same pins, never stored outside the worker.
		mkdir -p "$_kdir/certs/regdb" ||
			{ echo "ERROR: cannot create tree certs dir" >&2; return 1; }
		cp /keys/module-signing.pem "$_kdir/certs/module-signing.pem" &&
			chmod 600 "$_kdir/certs/module-signing.pem" ||
			{ echo "ERROR: cannot stage module signing key" >&2; return 1; }
		_rdb="$RECIPE_DIR/../wireless-regdb/files/saphira-regdb.x509"
		_rsha="118f8bf6bb8220bb23a8d3cb58359760976b5ba086376cdbc34db9a6d38afc07"
		[ -f "$_rdb" ] ||
			{ echo "ERROR: canonical regdb cert missing at $_rdb" >&2; return 1; }
		echo "$_rsha  $_rdb" | sha256sum -c - ||
			{ echo "ERROR: regdb cert failed its pin" >&2; return 1; }
		cp "$_rdb" "$_kdir/certs/regdb/saphira-regdb.x509" ||
			{ echo "ERROR: cannot stage regdb cert" >&2; return 1; }
		(cd "$_kdir" && make -j${JOBS:-$(nproc)}) ||
			{ echo "ERROR: kernel tree build failed" >&2; return 1; }
	fi
	[ -x "$_kdir/scripts/sign-file" ] ||
		{ echo "ERROR: $_kdir/scripts/sign-file not built" >&2; return 1; }
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
	kmod_prepare_tree "$_kshort" ||
		{ echo "ERROR: no usable kernel tree for $_kshort (self-prepare failed and none staged)" >&2; return 1; }
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
	# Declared maintainer hooks: refresh the module index for THIS release
	# after the module tree changes. Without them this package installs
	# cleanly and installs a module modprobe cannot find:
	#
	#   # apk add saphira-zfs-7.2.3      -> installs cleanly
	#   # ls /lib/modules/7.2.3/extra/   -> spl.ko zfs.ko  (correct vermagic)
	#   # modprobe zfs
	#   modprobe: FATAL: Module zfs not found in directory /lib/modules/7.2.3
	#
	# because modules.dep was generated when the KERNEL was installed and
	# knows nothing about extra/.
	#
	# The release is passed EXPLICITLY and is this package's own KVER, so
	# the hook can never reindex a different kernel than the one whose
	# tree it just changed. Bare `depmod -a' and `uname -r' are both
	# wrong here: the installed package may target a kernel other than the
	# running one (that is the entire point of a per-kernel variant), and a
	# blanket reindex would rewrite an unrelated release's module tree.
	#
	# post-deinstall is included because removal changes the tree too, and
	# apk runs it after the payload is gone, which is precisely when the
	# index must be rebuilt.
	#
	# A missing module tree is a legitimate no-op (the kernel package was
	# removed too, so there is nothing to index); a depmod that runs and
	# fails is not swallowed.
	install -d -m 0755 "$PKGDEST/usr/share/saphira/hooks.d/$pkgname"
	for _hook_kind in post-install post-upgrade post-deinstall; do
		cat > "$PKGDEST/usr/share/saphira/hooks.d/$pkgname/$_hook_kind" <<EOF
#!/bin/sh
# Generated by saphira-kernel/files/kmod-zfs.sh for $pkgname.
# Refresh the module index for $_kfull, the release this package ships.
# Absolute path, and it is /usr/sbin/depmod because that is where the
# kmod recipe installs it. The running host also carries an /sbin/depmod,
# but that is an unowned generation-zero symlink to ../bin/kmod rather
# than a packaged path: it works on Egg and fails on any root assembled
# from the repository. A disposable test root caught exactly that.
# apk passes the version as \$1; it is deliberately unused.
[ -d /lib/modules/$_kfull ] && /usr/sbin/depmod $_kfull
exit 0
EOF
		chmod 0755 "$PKGDEST/usr/share/saphira/hooks.d/$pkgname/$_hook_kind"
	done
}
