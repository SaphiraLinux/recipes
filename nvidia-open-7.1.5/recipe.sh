#!/bin/sh

pkgname=nvidia-open-7.1.5
pkgver=610.57.04
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='NVIDIA open kernel modules 610.57.04 for kernel 7.1.5 (kmods only; firmware is nvidia-open-firmware)'
license='MIT OR GPL-2.0'
origin=nvidia-open
repo=saphira
url=https://github.com/NVIDIA/open-gpu-kernel-modules
source=https://github.com/NVIDIA/open-gpu-kernel-modules/archive/refs/tags/610.57.04.tar.gz
sha256=619d7b5ce1f79c3211afdbf87d02b2174d268b10d005c5b8f994be22299be681

# Per-kernel co-installable output. Build logic lives in
# saphira-kernel/files/kmod-nvidia.sh; the kernel tree comes from staged
# /input (build-kmod-set.sh). New kernels: copy the nearest variant and
# set KVER_SHORT (see new-kmod-variant.sh).
# NOTE: the 7.1.5 tree at /usr/src/linux-7.1.5 currently lacks a built
# scripts/sign-file - run `make scripts` there before building this.
depends="kmod nvidia-open-firmware"
# Build secret contract: module signing is mandatory, never optional.
# The worker refuses before spending anything when the builder did
# not expose a readable /keys/module-signing.pem.
saphira_sign_key_required=yes
makedepends="
	binutils
	elfutils
	gawk
	gcc
	make
"
# Handover from the retired monolithic nvidia-open (owned these module
# paths plus firmware/doc): the file gate exempts retired names listed
# here, so the split successors absorb the paths without collision.
replaces="nvidia-open"

# CUDA policy: the Saphira host stays pure musl. CUDA runs inside a
# version-matched glibc systemd-nspawn container; only these kmods and
# the matching GSP firmware belong on the host.
KVER_SHORT=7.1.5

recipe_build()
{
	. "$RECIPE_DIR/../saphira-kernel/files/kmod-nvidia.sh"
	kmod_nvidia_build "$KVER_SHORT" \
		"$RECIPE_DIR/files/610.57.04.tar.gz" \
		"$sha256" "$RECIPE_DIR/files/0001-gate-fbdev-on-kconfig.patch"
}

recipe_install()
{
	. "$RECIPE_DIR/../saphira-kernel/files/kmod-nvidia.sh"
	kmod_nvidia_install "$KVER_SHORT" "$pkgver"
}
