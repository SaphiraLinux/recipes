#!/bin/sh

pkgname=saphira-drbd9-7.1.5
pkgver=9.3.3
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='DRBD 9.3.3 out-of-tree kernel modules for kernel 7.1.5 (Saphira-signed)'
license=GPL-2.0-or-later
origin=saphira-drbd9
repo=saphira
url=https://linbit.com/drbd/
# Multi-node DRBD (quorum, tiebreaker, 3+ nodes): the in-tree 8.4 driver
# cannot do this, hence the out-of-tree 9.x module. Managed at runtime
# by drbd-utils (separate recipe, covers 8.4/9.x drivers).
vendor=https://pkg.linbit.com/downloads/drbd/9/drbd-9.3.3.tar.gz
sha256=a7bfb016070c31df1c738569ca8cc5e5fc337dd449147f7bf62e746d87d38f21

# Per-kernel co-installable output. Build logic lives in
# saphira-kernel/files/kmod-drbd.sh; the kernel tree comes from staged
# /input (build-kmod-set.sh), the headers pin only provides host UAPI.
# New kernels: copy the nearest variant, set KVER_SHORT + headers pin
# (see new-kmod-variant.sh).
depends="kmod"

# Build secret contract: module signing is mandatory, never optional.
# The worker refuses before spending anything when the builder did
# not expose a readable /keys/module-signing.pem.
saphira_sign_key_required=yes
makedepends="
    bash
    binutils
    diffutils
    gawk
    gcc
    make
    patch
    perl
    saphira-kernel-headers=7.1.5
"

KVER_SHORT=7.1.5

recipe_build()
{
	. "$RECIPE_DIR/../saphira-kernel/files/kmod-drbd.sh"
	kmod_drbd_build "$KVER_SHORT" "$RECIPE_DIR/files/drbd-9.3.3.tar.gz" "$sha256"
}

recipe_install()
{
	. "$RECIPE_DIR/../saphira-kernel/files/kmod-drbd.sh"
	kmod_drbd_install "$KVER_SHORT"
}
