# linux-ccram: CCRAM Phase 1 test kernel (7.2.9 + CRAM series + sysram backend).
# Boots as a normal Saphira host with an N_MEMORY_PRIVATE tier carved from
# ordinary DRAM (uncompressed - this is a functional backend, not
# compressed RAM) managed by CRAM. Installs alongside every other kernel
# with its own /boot names and /lib/modules release; existing entries
# stay untouched as fallback.
#
# Base series: identical to linux-saphira-meta-cram (85 UPSTREAM + 18 FWD +
# 2 SKIP-UPSTREAM, byte-identical files), plus Saphira-original CCRAM
# patches under files/ccram/ (see CCRAM-PHASE1.md). KREL is 7.2.9-ccram.
pkgname=linux-ccram
kernel_version=${SAPHIRA_CCRAM_KERNEL_VERSION:-7.2.9}
pkgver=${kernel_version//-/_}
pkgrel=7
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="CCRAM Phase 1 test kernel ${kernel_version} (sysram private-node CRAM tier, uncompressed)"
license=GPL-2.0-only
origin=linux-ccram
repo=saphira
url=https://saphira.vm2.uk/

case "$kernel_version" in
	7.2.9)
		vendor=https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.2.9.tar.xz
		sha256=b4c5dfbe51a364a6c7f03869200f88c8e1f77403539005f14b7fc6bc91b8d8ba
		;;
	*) echo "ERROR: no pinned vendor/sha256 for ccram kernel $kernel_version" >&2; return 1 ;;
esac

# Build secret contract: module signing is mandatory, never optional.
saphira_sign_key_required=yes
makedepends="
	bc
	binutils
	kmod
	elfutils-dev
	bison
	m4
	flex
	gawk
	gcc
	openssl-dev
	make
	perl
	pahole
	zlib-dev
"

# Strict series application (see linux-saphira-meta-cram recipe.sh for the
# full rationale): --fuzz=0, fail closed on fuzz/malformed/reversed/FAILED.
# Line-number offsets are tolerated but visible in the build log; fuzz
# (ignored context) is refused. SKIP-* lines are markers, everything else
# with a path in $2 is applied in manifest order.
apply_one_strict()
{
	_f="$RECIPE_DIR/files/$1"
	_out=$(patch -Np1 --forward --fuzz=0 --no-backup-if-mismatch --dry-run -i "$_f" </dev/null 2>&1) \
		|| { echo "ERROR: series dry-run failed for $1" >&2; printf '%s\n' "$_out" >&2; return 1; }
	case "$_out" in
		*fuzz*|*malformed*|*garbage*|*Reversed*|*FAILED*|*failed*|*skip*|*Skip*)
			echo "ERROR: series entry not clean: $1" >&2
			printf '%s\n' "$_out" >&2
			return 1
			;;
	esac
	patch -Np1 --forward --fuzz=0 --no-backup-if-mismatch -i "$_f" </dev/null >&2 \
		|| { echo "ERROR: series apply failed for $1" >&2; return 1; }
}

apply_series_order()
{
	while IFS= read -r _line || [ -n "$_line" ]; do
		case "$_line" in
			''|'#'*) continue ;;
		esac
		set -- $_line
		case "$1" in
			SKIP-FWD|SKIP-UPSTREAM) echo "series: skip $2 ($1)" ;;
			UPSTREAM|FWD|CCRAMP1) apply_one_strict "$2" || return 1 ;;
			*) echo "ERROR: bad SERIES-ORDER line: $_line" >&2; return 1 ;;
		esac
	done < "$RECIPE_DIR/files/SERIES-ORDER"
}

# Config provenance gate (see files/ccram-config.fragment and
# files/CONFIG-DIFF-JUSTIFICATION.md): the shipped config must carry
# exactly the fragment's symbols with exactly the fragment's values,
# and no other CONFIG_CCRAM_* symbol. Any future delta must extend
# the fragment and the justification together — an unexplained config
# line fails the build, never ships silently.
check_ccram_config_delta()
{
	_cfg="$1"
	while IFS= read -r _line || [ -n "$_line" ]; do
		case "$_line" in
			''|'#'*) continue ;;
			CONFIG_*=*)
				_sym=${_line%%=*}; _want=${_line#*=}
				_got=$(grep -E "^${_sym}=" "$_cfg" || true)
				[ "$_got" = "$_line" ] || {
					echo "ERROR: config delta mismatch: want [$_line], have [$_got]" >&2
					return 1
				}
				;;
		esac
	done < "$RECIPE_DIR/files/ccram-config.fragment"
	_extra=$(grep -E "^CONFIG_CCRAM_" "$_cfg" | grep -vE "^CONFIG_CCRAM_SYSRAM=y$" || true)
	[ -z "$_extra" ] || {
		echo "ERROR: unexplained CONFIG_CCRAM_* in shipped config:" >&2
		printf '%s\n' "$_extra" >&2
		return 1
	}
}

# Post-resolution assertion: the symbols olddefconfig is documented to
# select (see ccram-config.fragment) must be present with exactly these
# values in the final .config. Catches a resolution flip or an
# unexpected extra selection.
check_ccram_resolved_extras()
{
	_cfg="$1"
	for _want in \
		'CONFIG_DRM_CLIENT_SETUP=y' \
		'CONFIG_DRM_CLIENT_DEFAULT_FBDEV=y' \
		'CONFIG_DRM_CLIENT_DEFAULT="fbdev"' \
		'CONFIG_FRAMEBUFFER_CONSOLE_DETECT_PRIMARY=y'
	do
		_sym=${_want%%=*}
		_got=$(grep -E "^${_sym}=|^# ${_sym} " "$_cfg" || true)
		[ "$_got" = "$_want" ] || {
			echo "ERROR: resolved config mismatch: want [$_want], have [$_got]" >&2
			return 1
		}
	done
}

recipe_build()
{
	KEY=/keys/module-signing.pem
	if [ ! -e "$KEY" ]; then
		echo "ERROR: module signing key not exposed at $KEY (builder key configuration?)" >&2
		return 1
	fi
	if [ ! -r "$KEY" ]; then
		echo "ERROR: module signing key exposed but unreadable at $KEY (UID ACL missing on the host key? builds must never go unsigned)" >&2
		return 1
	fi
	export TAR_OPTIONS=--no-same-owner

	KBALL="$RECIPE_DIR/files/linux-${kernel_version}.tar.xz"
	[ -f "$KBALL" ] || KBALL="$RECIPE_DIR/files/linux-${kernel_version}.tar.gz"
	if [ -f "$KBALL" ]; then
		echo "$sha256  $KBALL" | sha256sum -c -
	else
		[ -n "${SOURCE_ARCHIVE-}" ] && [ -f "$SOURCE_ARCHIVE" ] \
			|| { echo "ERROR: no local linux-${kernel_version}.tar.{xz,gz} and no fetched SOURCE_ARCHIVE" >&2; return 1; }
		KBALL=$SOURCE_ARCHIVE
	fi
	mkdir -p "$SRC/linux-${kernel_version}"
	tar --no-same-owner -C "$SRC/linux-${kernel_version}" --strip-components=1 -xf "$KBALL"
	cd "$SRC/linux-${kernel_version}"

	# Saphira uarch policy (7.2.9-refreshed context, strict-gated).
	apply_one_strict x86-64-v3.patch || return 1
	# CRAM/private-memory series + CCRAM patches, strictly gated.
	apply_series_order

	cp "$RECIPE_DIR/files/config-${kernel_version}-ccram-akadata" "$SRC/linux-${kernel_version}/.config"
	check_ccram_config_delta "$SRC/linux-${kernel_version}/.config" || return 1
	mkdir -p "$SRC/linux-${kernel_version}/certs/regdb"
	cp "$RECIPE_DIR/files/saphira-regdb.x509" "$SRC/linux-${kernel_version}/certs/regdb/saphira-regdb.x509"
	cp "$KEY" "$SRC/linux-${kernel_version}/certs/module-signing.pem"
	chmod 600 "$SRC/linux-${kernel_version}/certs/module-signing.pem"

	make olddefconfig
	# Config provenance gate, asserted on the RESOLVED config (not the
	# seed): olddefconfig is allowed to add selected symbols, but the
	# fragment's symbols must survive resolution with exactly the
	# fragment's values, and no other CONFIG_CCRAM_* may appear.
	# Asserting only the pre-resolution seed would miss a resolution
	# flip; asserting the final .config is what the payload is built
	# from. The earlier seed check (above) stays as a fail-fast check.
	check_ccram_config_delta "$SRC/linux-${kernel_version}/.config" || return 1
	check_ccram_resolved_extras "$SRC/linux-${kernel_version}/.config" || return 1
	# No-initramfs builtin policy, same gate as production kernels.
	. "$RECIPE_DIR/files/check-no-initramfs-builtins.sh"
	check_no_initramfs_builtins "$SRC/linux-${kernel_version}/.config" "$kernel_version"
	make -j${JOBS:-$(nproc)}

}

recipe_install()
{
	# Same defence-in-depth as saphira-kernel: config asserts no DWARF,
	# INSTALL_MOD_STRIP guarantees no debug payload in any runtime .ko.
	make INSTALL_MOD_PATH="$PKGDEST" INSTALL_MOD_STRIP=1 modules_install
	install -d "$PKGDEST/boot"
	install -m 644 "$SRC/linux-${kernel_version}/arch/x86/boot/bzImage" "$PKGDEST/boot/vmlinuz-${kernel_version}-ccram"
	install -m 644 "$SRC/linux-${kernel_version}/System.map" "$PKGDEST/boot/System.map-${kernel_version}-ccram"
	install -m 644 "$SRC/linux-${kernel_version}/.config" "$PKGDEST/boot/config-${kernel_version}-ccram"
	# No /usr/src, no build/source symlinks: runtime package, and
	# /build constructor state must never leak into payloads.
	. "$RECIPE_DIR/files/install-kernel-layout.sh"
	KREL=$(kernel_layout_release "$SRC/linux-${kernel_version}")
	rm -f "$PKGDEST/lib/modules/$KREL/build" "$PKGDEST/lib/modules/$KREL/source"
	check_module_layout "$PKGDEST" "$KREL" "$KREL"
	depmod -b "$PKGDEST" $KREL
	# Boot-menu lifecycle: same GRUB hook as production kernels so the
	# new entry appears and the existing entries keep working.
	install -d -m 0755 "$PKGDEST/usr/share/saphira/hooks.d/$pkgname"
	install -m 0755 "$RECIPE_DIR/files/hooks-grub-mkconfig" \
		"$PKGDEST/usr/share/saphira/hooks.d/$pkgname/post-install"
	install -m 0755 "$RECIPE_DIR/files/hooks-grub-mkconfig" \
		"$PKGDEST/usr/share/saphira/hooks.d/$pkgname/post-upgrade"
}
