#!/bin/sh

pkgname=saphira-zfs-7.2.9-ccram
pkgver=2.4.4
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='OpenZFS 2.4.4 kernel modules for kernel 7.2.9-ccram (kmods only; userspace is saphira-zfs-userspace)'
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
# Kernel identity is the line (KVER_SHORT), not the packaging revision:
# the package name carries the kver, the build tree is the staged
# /usr/src/linux-<kver> tree, and modules land under that KREL's extra/.
# -rN is packaging metadata and stays out of the ABI dependency policy;
# rebuilds follow source/config/KREL changes (release process), and the
# build-time staged-tree config gate enforces exact-tree builds.
depends="kmod saphira-zfs-userspace linux-ccram"
# Build secret contract: module signing is mandatory, never optional.
# The worker refuses before spending anything when the builder did
# not expose a readable /keys/module-signing.pem.
saphira_sign_key_required=yes
# saphira-kernel-headers stays kver-only (bare name, host UAPI only;
# the build tree comes from staged /input). -rN never enters kmod deps.
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
# Handover from the retired monolithic saphira-zfs (owned these module
# paths): the file gate exempts retired names listed here, so the split
# successors absorb the paths without collision.
replaces="saphira-zfs"

# Pool compatibility: mounts existing 2.4.1 / 2.4.3 pools; do NOT zpool upgrade.
KVER_SHORT=7.2.9-ccram

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
