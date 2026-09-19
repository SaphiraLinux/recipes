#!/bin/sh

pkgname=saphira-zfs-userspace
pkgver=2.4.4
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='OpenZFS 2.4.4 userspace (zpool, zfs, libraries, man pages; kernel modules are saphira-zfs-<kver>)'
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
	saphira-kernel-headers
	make
	pkgconf
	python3
"
# Handover from the retired monolithic saphira-zfs (owned userspace,
# man pages and docs): the file gate exempts retired names listed here.
replaces="saphira-zfs"

# Needs a configured kernel tree for --with-linux, so this also takes
# the /input staging directory (any staged tree will do; userspace is
# kernel-independent). Assemble with:
#   /recipes//recipes/saphira-kernel/files/stage-kmod-input.sh /build/kernel-input
#   buildpkg saphira-zfs-userspace /build/kernel-input
# Pool compatibility: mounts existing 2.4.1 / 2.4.3 pools; do NOT zpool upgrade.

recipe_build()
{
	export TAR_OPTIONS=--no-same-owner
	# Newest staged tree configures the build; the output does not depend
	# on which one (fail closed when none is staged).
	KDIR=$(for d in "$SRC"/linux-*/; do [ -d "$d" ] && printf '%s\n' "$d"; done | sort -V | tail -1)
	[ -n "$KDIR" ] && [ -f "$KDIR/Makefile" ] || { echo "ERROR: no staged kernel tree under $SRC (staged /input?)" >&2; return 1; }

	ZSRCBALL="$RECIPE_DIR/files/zfs-2.4.4.tar.gz"
	echo "$zfs_sha256  $ZSRCBALL" | sha256sum -c -
	mkdir -p "$SRC/zfs"
	tar --no-same-owner -C "$SRC/zfs" --strip-components=1 -xf "$ZSRCBALL"
	cd "$SRC/zfs"

	./configure --prefix=/usr --sysconfdir=/etc \
		--localstatedir=/var \
		--with-linux="$KDIR" --with-linux-obj="$KDIR" \
		--with-config=all
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
	# Kernel modules ship in the per-kernel saphira-zfs-<kver> packages,
	# never here: drop whatever this configure's kernel produced so the
	# two outputs can never collide.
	rm -rf -- "$PKGDEST/lib/modules"
}
