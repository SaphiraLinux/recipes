pkgname=saphira-zfs
pkgver=2.4.4
pkgrel=4
pkgarch=${SAPHIRA_ARCH:-x86_64}
disabled=yes
disabled_reason='superseded by the per-kernel saphira-zfs-7.1.5 / saphira-zfs-7.2.2 + saphira-zfs-userspace split (co-installable outputs; replaces=saphira-zfs handover)'
pkgdesc='OpenZFS 2.4.4 kmod + userspace for kernel 7.1.5 (no DKMS, Saphira-signed)'
license=CDDL
origin=saphira-zfs
repo=saphira
url=https://github.com/openzfs/zfs
# Upstream release tarball, vendored (bytes pinned; releases are stable):
# https://github.com/openzfs/zfs/releases/download/zfs-2.4.4/zfs-2.4.4.tar.gz
zfs_sha256=2a3c70d55a37cc71618a95a60e81ad66530201eb118d37741dc92efcf848c8b1

depends="libtirpc curl util-linux openssl"
makedepends="
	binutils
	gcc
	gawk
	kmod
	libtirpc-dev
	curl-dev
	elfutils-dev
	util-linux-dev
	zlib-dev
	openssl-dev
	saphira-kernel-headers=7.2.2
	make
	pkgconf
	python3
"

# Build inputs supplied via the /input staging directory. Assemble with:
#   /recipes/saphira-kernel/files/stage-kmod-input.sh /build/zfs-input
#   buildpkg saphira-zfs /build/zfs-input
# Pool compatibility: mounts existing 2.4.1 / 2.4.3 pools; do NOT zpool upgrade.

recipe_build()
{
	export TAR_OPTIONS=--no-same-owner
	KDIR="$SRC/linux-7.2.2"
	KEY=/keys/module-signing.pem
	[ -f "$KDIR/Makefile" ] || { echo "ERROR: kernel build tree missing at $KDIR (staged /input?)" >&2; return 1; }
	if [ ! -e "$KEY" ]; then
		echo "ERROR: module signing key not exposed at $KEY (builder key configuration?)" >&2
		return 1
	fi
	if [ ! -r "$KEY" ]; then
		echo "ERROR: module signing key exposed but unreadable at $KEY (UID ACL missing on the host key? builds must never go unsigned)" >&2
		return 1
	fi
	[ -x "$KDIR/scripts/sign-file" ] || { echo "ERROR: $KDIR/scripts/sign-file not built" >&2; return 1; }

	ZSRCBALL="$RECIPE_DIR/files/zfs-2.4.4.tar.gz"
	echo "$zfs_sha256  $ZSRCBALL" | sha256sum -c -
	mkdir -p "$SRC/zfs"
	tar --no-same-owner -C "$SRC/zfs" --strip-components=1 -xf "$ZSRCBALL"
	cd "$SRC/zfs"

	./configure --prefix=/usr --sysconfdir=/etc \
		--with-linux="$KDIR" --with-linux-obj="$KDIR" \
		--with-config=all
	make -j${JOBS:-$(nproc)}

	for ko in module/*.ko; do
		"$KDIR/scripts/sign-file" sha256 "$KEY" "$KEY" "$ko"
	done
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
	install -d "$PKGDEST/lib/modules/7.2.2/extra"
	install -m 644 "$SRC/zfs/module/zfs.ko" "$SRC/zfs/module/spl.ko" \
		"$PKGDEST/lib/modules/7.2.2/extra/"
}
