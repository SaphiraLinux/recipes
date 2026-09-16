pkgname=saphira-kernel
pkgver=${SAPHIRA_KERNEL_VERSION:-7.2.2}
pkgrel=6
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Saphira kernel ${pkgver} (x86-64-v3, signed modules, Saphira regdb trust)"
license=GPL-2.0-only
origin=saphira-kernel
repo=saphira
url=https://saphira.vm2.uk/
# Upstream kernel tarball per version line (SAPHIRA_KERNEL_VERSION selects).
# vendor=+sha256= is the fetch contract: when the archive is absent from
# files/, the builder downloads vendor=, verifies sha256, and exposes the
# verified archive as $SOURCE_ARCHIVE (kernel.org signs the UNCOMPRESSED
# .tar; verify procedure: xz -dc file.xz > file.tar && gpg --verify
# file.tar.sign file.tar). 7.3-rc1 is a torvalds-tree cgit snapshot
# (unsigned by nature; TLS fetch + sha256 pin, same as other payloads).
case "$pkgver" in
	7.1.5)
		vendor=https://mirrors.edge.kernel.org/pub/linux/kernel/v7.x/linux-7.1.5.tar.xz
		sha256=22a0196b3cbcdf34dc27b77561f4d040585fd3447edc9ab3531a1ac79e3041e7
		;;
	7.2.2)
		vendor=https://mirrors.edge.kernel.org/pub/linux/kernel/v7.x/linux-7.2.2.tar.xz
		sha256=7d0e7ce14f98c43efe880cffbf354a59be45928fdf7170d7333c374ae91c0d83
		;;
	7.2.3)
		vendor=https://mirrors.edge.kernel.org/pub/linux/kernel/v7.x/linux-7.2.3.tar.xz
		sha256=8ba259e8e7b13ec6ef0941c8a39ad90b24bd4a4d6c0010ba6bafb794550ecd03
		;;
	7.3-rc1)
		vendor=https://git.kernel.org/torvalds/t/linux-7.3-rc1.tar.gz
		sha256=8d36fbfc7c8906ccfa1ebacc30f84998406504c3f13733a040bb3a3fbe8ac270
		;;
	*) echo "ERROR: no pinned vendor/sha256 for kernel $pkgver" >&2; return 1 ;;
esac

# Build secret contract: module signing is mandatory, never optional.
# The worker refuses before spending anything when the builder did
# not expose a readable /keys/module-signing.pem.
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
"

# Build inputs: none beyond the recipe tree. The module signing key is
# exposed by the builder (fixed in-namespace path); no /input staging.
# Regdb trust: public DER cert ships in files/ and is compiled into cfg80211
# via CONFIG_CFG80211_EXTRA_REGDB_KEYDIR. Saphira policy patches live in
# files/: x86-64-v3.patch, config-${pkgver}-akadata.

recipe_build()
{
	# Module signing key: exposed by the builder read-only at the fixed
	# in-namespace path /keys/module-signing.pem (canonical host key
	# /etc/saphira/keys/module-signing.pem, never in /recipes, never
	# staged through /build). Absent key fails closed below.
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

	# Local archive wins when present (verified, never re-downloaded);
	# otherwise build from the builder-verified $SOURCE_ARCHIVE.
	KBALL="$RECIPE_DIR/files/linux-${pkgver}.tar.xz"
	[ -f "$KBALL" ] || KBALL="$RECIPE_DIR/files/linux-${pkgver}.tar.gz"
	if [ -f "$KBALL" ]; then
		echo "$sha256  $KBALL" | sha256sum -c -
	else
		[ -n "${SOURCE_ARCHIVE-}" ] && [ -f "$SOURCE_ARCHIVE" ] \
			|| { echo "ERROR: no local linux-${pkgver}.tar.{xz,gz} and no fetched SOURCE_ARCHIVE" >&2; return 1; }
		KBALL=$SOURCE_ARCHIVE
	fi
	mkdir -p "$SRC/linux-${pkgver}"
	tar --no-same-owner -C "$SRC/linux-${pkgver}" --strip-components=1 -xf "$KBALL"
	cd "$SRC/linux-${pkgver}"

	patch -Np1 -i "$RECIPE_DIR/files/x86-64-v3.patch"
	cp "$RECIPE_DIR/files/config-${pkgver}-akadata" "$SRC/linux-${pkgver}/.config"
	mkdir -p "$SRC/linux-${pkgver}/certs/regdb"
	cp "$RECIPE_DIR/files/saphira-regdb.x509" "$SRC/linux-${pkgver}/certs/regdb/saphira-regdb.x509"
	cp "$KEY" "$SRC/linux-${pkgver}/certs/module-signing.pem"
	chmod 600 "$SRC/linux-${pkgver}/certs/module-signing.pem"

	make olddefconfig
	make -j${JOBS:-$(nproc)}

}

recipe_install()
{
	make INSTALL_MOD_PATH="$PKGDEST" modules_install
	install -d "$PKGDEST/boot"
	install -m 644 "$SRC/linux-${pkgver}/arch/x86/boot/bzImage" "$PKGDEST/boot/vmlinuz-${pkgver}-akadata"
	install -m 644 "$SRC/linux-${pkgver}/System.map" "$PKGDEST/boot/System.map-${pkgver}-akadata"
	install -m 644 "$SRC/linux-${pkgver}/.config" "$PKGDEST/boot/config-${pkgver}-akadata"
	# Installed module-tree layout (Saphira policy): upstream
	# modules_install bakes the absolute build-tree path into
	# lib/modules/<release>/{build,source} - constructor state under
	# /build that must never leak into the installed filesystem.
	# Replace with the versioned prepared-tree layout (see
	# files/install-kernel-layout.sh): /usr/src/linux-<pkgver>-saphira
	# owned by this package, build pointing at it directly (never via
	# the floating /usr/src/linux convenience pointer, which stays
	# admin-managed so co-installed kernels never fight over it).
	# saphira-kernel-headers stays UAPI-only and is unrelated to this
	# tree. KREL is the true kernel release (differs from pkgver on
	# -rc lines); depmod and the module dir both use it.
	. "$RECIPE_DIR/files/install-kernel-layout.sh"
	KREL=$(kernel_layout_release "$SRC/linux-${pkgver}")
	install_prepared_tree "$SRC/linux-${pkgver}" "$PKGDEST/usr/src/linux-${pkgver}-saphira"
	install_module_build_link "$PKGDEST" "$KREL" "linux-${pkgver}-saphira"
	check_module_layout "$PKGDEST" "$KREL" "linux-${pkgver}-saphira" "$KREL"
	depmod -b "$PKGDEST" $KREL
}
