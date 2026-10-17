# linux-saphira-meta-cram: test kernel carrying Meta/Gregory Price
# CRAM + private-memory work on a 7.2.9 base. Hatchling test use only:
# it installs alongside (never instead of) saphira-kernel, keeps its
# own /boot names and /lib/modules release, and stays visible in GRUB
# so the normal kernel remains the fallback throughout the experiment.
#
# Revision pinning, backend conclusion and per-patch dispositions live in
# files/CRAM.PROVENANCE and files/GATE-REPORT.md; files/SERIES-ORDER is
# the authoritative application manifest (85 UPSTREAM + 16 FWD +
# 2 SKIP-UPSTREAM, all 103 upstream commits accounted, byte-identical
# upstream files under files/series/, adaptations only in files/fwd/).
pkgname=linux-saphira-meta-cram
kernel_version=${SAPHIRA_CRAM_KERNEL_VERSION:-7.2.9}
# Saphira pre-release convention (underscore, never hyphen before -rN).
# 7.2.9 is stable so no translation applies; kept as the same expansion
# the kernel recipe uses so a future -rc line behaves identically.
pkgver=${kernel_version//-/_}
pkgrel=2
# r2: build in i915/simpledrm/bochs/qxl + fbdev emulation (early
# console and VM displays need builtin drivers; no initramfs).
# Payload change.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Saphira CRAM test kernel ${kernel_version} (private NUMA nodes + compressed-RAM tier, hatchling only)"
license=GPL-2.0-only
origin=linux-saphira-meta-cram
repo=saphira
url=https://saphira.vm2.uk/

# Upstream tarball (vendor= + sha256= fetch contract, same as saphira-kernel).
case "$kernel_version" in
	7.2.9)
		vendor=https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.2.9.tar.xz
		sha256=b4c5dfbe51a364a6c7f03869200f88c8e1f77403539005f14b7fc6bc91b8d8ba
		;;
	*) echo "ERROR: no pinned vendor/sha256 for cram kernel $kernel_version" >&2; return 1 ;;
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

# Strict series application.
#
# The forward-port gate for this series was `git apply --check` per patch
# in order (exact context match, no fuzz). The build worker is only
# guaranteed patch(1), so the recipe re-enforces strictness here with
# --fuzz=0 and fails closed on any fuzz/malformed/reversed notice.
#
# A note on "offset" notices: patch(1) prints "offset N lines" whenever
# a hunk's @@ line numbers don't match the file byte-for-byte, even when
# every context line matches exactly (line numbers drift as earlier
# series entries land — the same search git-apply performs silently).
# Offsets are therefore observable but NOT fatal; fuzz (ignored context)
# is what loses information and is refused. The dry-run output is left
# in the build log so any offset is auditable, never silent.
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
			UPSTREAM|FWD) apply_one_strict "$2" || return 1 ;;
			SKIP-FWD|SKIP-UPSTREAM) echo "series: skip $2 ($1)" ;;
			*) echo "ERROR: bad SERIES-ORDER line: $_line" >&2; return 1 ;;
		esac
	done < "$RECIPE_DIR/files/SERIES-ORDER"
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

	# Saphira uarch policy first (same intent as production kernels;
	# vendored copy has 7.2.9-refreshed context, strict-gated as well).
	apply_one_strict x86-64-v3.patch || return 1
	# CRAM/private-memory series, strictly gated (see apply_one_strict).
	apply_series_order

	cp "$RECIPE_DIR/files/config-${kernel_version}-meta-cram-akadata" "$SRC/linux-${kernel_version}/.config"
	mkdir -p "$SRC/linux-${kernel_version}/certs/regdb"
	# Canonical regdb trust anchor: single copy in wireless-regdb/files/,
	# staged through $SRC (under /build) with sha256 verification.
	# Preserved bytes (sha256 118f8bf6bb8220bb23a8d3cb58359760976b5ba086376cdbc34db9a6d38afc07);
	# regenerating would break regulatory.db verification. Legacy
	# per-recipe files/ copies are removed; do not re-vendor.
	REGDB_CANONICAL="$RECIPE_DIR/../wireless-regdb/files/saphira-regdb.x509"
	REGDB_SHA="118f8bf6bb8220bb23a8d3cb58359760976b5ba086376cdbc34db9a6d38afc07"
	[ -f "$REGDB_CANONICAL" ] || { echo "ERROR: canonical regdb cert missing at $REGDB_CANONICAL" >&2; return 1; }
	echo "$REGDB_SHA  $REGDB_CANONICAL" | sha256sum -c - || return 1
	STAGED_REGDB="$SRC/saphira-regdb.x509"
	cp "$REGDB_CANONICAL" "$STAGED_REGDB"
	echo "$REGDB_SHA  $STAGED_REGDB" | sha256sum -c - || return 1
	cp "$STAGED_REGDB" "$SRC/linux-${kernel_version}/certs/regdb/saphira-regdb.x509"
	cp "$KEY" "$SRC/linux-${kernel_version}/certs/module-signing.pem"
	chmod 600 "$SRC/linux-${kernel_version}/certs/module-signing.pem"

	make olddefconfig
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
	install -m 644 "$SRC/linux-${kernel_version}/arch/x86/boot/bzImage" "$PKGDEST/boot/vmlinuz-${kernel_version}-meta-cram"
	install -m 644 "$SRC/linux-${kernel_version}/System.map" "$PKGDEST/boot/System.map-${kernel_version}-meta-cram"
	install -m 644 "$SRC/linux-${kernel_version}/.config" "$PKGDEST/boot/config-${kernel_version}-meta-cram"
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
