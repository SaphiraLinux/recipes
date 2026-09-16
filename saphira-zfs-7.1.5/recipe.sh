#!/bin/sh

pkgname=saphira-zfs-7.1.5
pkgver=2.4.4
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='OpenZFS 2.4.4 kernel modules for kernel 7.1.5 (kmods only; userspace is saphira-zfs-userspace)'
license=CDDL
origin=saphira-zfs
repo=saphira
url=https://github.com/openzfs/zfs
source=https://github.com/openzfs/zfs/releases/download/zfs-2.4.4/zfs-2.4.4.tar.gz
sha256=2a3c70d55a37cc71618a95a60e81ad66530201eb118d37741dc92efcf848c8b1

# Per-kernel co-installable output. Build logic lives in
# saphira-kernel/files/kmod-zfs.sh; the kernel tree comes from staged
# /input (build-kmod-set.sh), the headers pin only provides host UAPI.
# New kernels: copy the nearest variant, set KVER_SHORT + headers pin
# (see new-kmod-variant.sh).
depends="kmod saphira-zfs-userspace"
# Build secret contract: module signing is mandatory, never optional.
# The worker refuses before spending anything when the builder did
# not expose a readable /keys/module-signing.pem.
saphira_sign_key_required=yes
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
	saphira-kernel-headers=7.1.5
	make
	pkgconf
	python3
"
# Handover from the retired monolithic saphira-zfs (owned these module
# paths): the file gate exempts retired names listed here, so the split
# successors absorb the paths without collision.
replaces="saphira-zfs"

# Pool compatibility: mounts existing 2.4.1 / 2.4.3 pools; do NOT zpool upgrade.
KVER_SHORT=7.1.5

recipe_build()
{
	. "$RECIPE_DIR/../saphira-kernel/files/kmod-zfs.sh"
	kmod_zfs_build "$KVER_SHORT" "$RECIPE_DIR/files/zfs-2.4.4.tar.gz" "$sha256"
}

recipe_install()
{
	. "$RECIPE_DIR/../saphira-kernel/files/kmod-zfs.sh"
	kmod_zfs_install "$KVER_SHORT"
}
