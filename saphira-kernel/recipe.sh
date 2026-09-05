pkgname=saphira-kernel
pkgver=${SAPHIRA_KERNEL_VERSION:-7.2.2}
pkgrel=5
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Saphira kernel ${pkgver} (x86-64-v3, signed modules, Saphira regdb trust)"
license=GPL-2.0-only
origin=saphira-kernel
repo=saphira
url=https://saphira.vm2.uk/
# Upstream kernel tarball, vendored + PGP-verified (kernel.org signs the UNCOMPRESSED .tar;
# verify procedure: xz -dc file.xz > file.tar && gpg --verify file.tar.sign file.tar):
# https://mirrors.edge.kernel.org/pub/linux/kernel/v7.x/linux-${pkgver}.tar.xz
# 7.3-rc1 is a torvalds-tree cgit snapshot (unsigned by nature; TLS fetch +
# sha256 pin, same as other vendored payloads):
# https://git.kernel.org/torvalds/t/linux-7.3-rc1.tar.gz
case "$pkgver" in
	7.1.5) linux_sha256=22a0196b3cbcdf34dc27b77561f4d040585fd3447edc9ab3531a1ac79e3041e7 ;;
	7.2.2) linux_sha256=7d0e7ce14f98c43efe880cffbf354a59be45928fdf7170d7333c374ae91c0d83 ;;
	7.2.3) linux_sha256=8ba259e8e7b13ec6ef0941c8a39ad90b24bd4a4d6c0010ba6bafb794550ecd03 ;;
	7.3-rc1) linux_sha256=8d36fbfc7c8906ccfa1ebacc30f84998406504c3f13733a040bb3a3fbe8ac270 ;;
	*) echo "ERROR: no pinned sha256 for kernel $pkgver" >&2; return 1 ;;
esac

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

# Build inputs supplied via the /input staging directory:
#   buildpkg saphira-kernel /build/kernel-input
#   /build/kernel-input/saphira-module.pem   module signing key (never in /recipes)
# Regdb trust: public DER cert ships in files/ and is compiled into cfg80211
# via CONFIG_CFG80211_EXTRA_REGDB_KEYDIR. Saphira policy patches live in
# files/: x86-64-v3.patch, config-${pkgver}-akadata.

recipe_build()
{
	# Module signing key: supplied via the /input staging directory
	# (buildpkg saphira-kernel /build/kernel-input); $SRC copy kept
	# as fallback for hand-staged manual builds. buildpkg binds
	# /input but nothing copies it into $SRC, so read it directly.
	KEY="$SRC/saphira-module.pem"
	[ -f "$KEY" ] || KEY=/input/saphira-module.pem
	[ -f "$KEY" ] || { echo "ERROR: module signing key missing at $KEY (staged /input?)" >&2; return 1; }
	export TAR_OPTIONS=--no-same-owner

	KBALL="$RECIPE_DIR/files/linux-${pkgver}.tar.xz"
	[ -f "$KBALL" ] || KBALL="$RECIPE_DIR/files/linux-${pkgver}.tar.gz"
	echo "$linux_sha256  $KBALL" | sha256sum -c -
	mkdir -p "$SRC/linux-${pkgver}"
	tar --no-same-owner -C "$SRC/linux-${pkgver}" --strip-components=1 -xf "$KBALL"
	cd "$SRC/linux-${pkgver}"

	patch -Np1 -i "$RECIPE_DIR/files/x86-64-v3.patch"
	cp "$RECIPE_DIR/files/config-${pkgver}-akadata" "$SRC/linux-${pkgver}/.config"
	mkdir -p "$SRC/linux-${pkgver}/certs/regdb"
	cp "$RECIPE_DIR/files/saphira-regdb.x509" "$SRC/linux-${pkgver}/certs/regdb/saphira-regdb.x509"
	cp "$KEY" "$SRC/linux-${pkgver}/certs/saphira-module.pem"
	chmod 600 "$SRC/linux-${pkgver}/certs/saphira-module.pem"

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
	depmod -b "$PKGDEST" $pkgver
}
