#!/bin/sh

pkgname=gpu-unlock-7.2.2
pkgver=2.0.0
pkgrel=1
# r1: first revision. gpu-unlock 2.0.0 at upstream commit 7eb51bc
# (private fork https://github.com/akadata/gpu-unlock, main) plus the
# pre-extracted NVIDIA 610.43.03 GSP firmware set, built for KREL 7.2.2.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='gpu-unlock 2.0.0 tensor-throughput unlock kmod for kernel 7.2.2 (opt-in, inert by default)'
license=GPL-2.0-only
origin=gpu-unlock
repo=saphira
url=https://github.com/akadata/gpu-unlock
# Private fork: public builders cannot fetch it, so (like the
# saphira-bucket precedent) the bytes are vendored and the URL
# documents provenance. Release v2.0.0 carries the exact vendored
# bytes (git-archive of commit 7eb51bc); the builder verifies
# files/<basename> against sha256= and never re-downloads it.
vendor=https://github.com/akadata/gpu-unlock/releases/download/v2.0.0/gpu-unlock-2.0.0.tar.xz
sha256=055daac1a20cbd2b8424ee4b8a848c1ae6c958f20cbbf2a42c13299c58c4470a
# Pre-extracted NVIDIA 610.43.03 GSP firmware (16 blobs, 80.7M xz):
# the offline builder cannot run the NVIDIA installer, and the blobs
# are byte-stable inputs, so they ship as a deterministic archive
# with a sidecar, exactly like any other vendored source.
fw_sha256=29c26b54142a8a5b6b4f181189bfd90e726441559919d1c403bc1c3de7c4fdaf

# What this is (and is not): an out-of-tree module that modifies
# NVIDIA GPU initialisation to unlock otherwise restricted hardware
# tensor-core throughput on supported GPUs. Proven on RTX 3060 GA106:
# sustained BF16 26.5 -> ~47.5 TFLOPS, similar FP16/TF32, FP32
# unchanged. NOT an overclock, VRAM expansion, or vGPU
# implementation. Activation is operator opt-in only (kernel parameter
# gpu_unlock.targets=all plus early load before nvidia binds); the
# package itself loads nothing. See README.Saphira in the payload.
#
# Version coupling (proven matrix, live on homer): gpu-unlock 2.0.0 +
# this 610.43.03 firmware set + NVIDIA driver 610.57.04
# (nvidia-open-7.2.2). The module carries its own GSP boot chain in
# its own firmware directory and binds pre-driver; do not mix other
# releases on either side.

# Per-kernel co-installable output. Build logic lives in
# saphira-kernel/files/kmod-gpu-unlock.sh; the kernel tree is prepared
# inside the worker (published config + sibling sources, no staging).
# New kernels: copy the nearest
# variant and set KVER_SHORT (see new-kmod-variant.sh).
depends="kmod nvidia-open-7.2.2"

# Build secret contract: module signing is mandatory, never optional.
# The worker refuses before spending anything when the builder did
# not expose a readable /keys/module-signing.pem.
saphira_sign_key_required=yes
# Kbuild needs the toolchain plus host UAPI; the module tree comes
# from staged /input (same contract as kmod-drbd.sh). No patches are
# applied, so no patch/diffutils lines.
# Hermetic in-worker kernel prepare: unpack + patches + olddefconfig +
# modules_prepare all run inside the worker (no staged /input), so the
# closure is the kernel-prepare closure (andrews-kernel line, minus
# pahole/BTF which a prepare does not consume).
makedepends="
	bc
	binutils
	elfutils-dev
	bison
	m4
	flex
	gawk
	gcc
	make
	openssl-dev
	patch
	perl
	elfutils
	saphira-linux-uapi-headers
"

KVER_SHORT=7.2.2

recipe_build()
{
	. "$RECIPE_DIR/../saphira-kernel/files/kmod-gpu-unlock.sh"
	kmod_gpu_unlock_build "$KVER_SHORT" \
		"$RECIPE_DIR/files/gpu-unlock-2.0.0.tar.xz" "$sha256"
}

recipe_install()
{
	. "$RECIPE_DIR/../saphira-kernel/files/kmod-gpu-unlock.sh"
	kmod_gpu_unlock_install "$KVER_SHORT" \
		"$RECIPE_DIR/files/gpu-unlock-firmware-610.43.03.tar.xz" "$fw_sha256"
}
