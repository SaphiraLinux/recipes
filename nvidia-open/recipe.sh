#!/bin/sh

pkgname=nvidia-open
pkgver=610.57.04
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='NVIDIA open kernel modules 610.57.04 for kernel 7.2.2 (kmods + GSP firmware only, NO CUDA userspace)'
license='MIT OR GPL-2.0'
origin=nvidia-open
repo=saphira
url=https://github.com/NVIDIA/open-gpu-kernel-modules
# Vendored: https://github.com/NVIDIA/open-gpu-kernel-modules/archive/refs/tags/610.57.04.tar.gz
nvidia_open_sha256=619d7b5ce1f79c3211afdbf87d02b2174d268b10d005c5b8f994be22299be681
# GSP firmware vendored from NVIDIA-Linux-x86_64-610.57.04.run (same
# release: NVIDIA kernel/userspace/GSP version coupling is strict).
gsp_ga10x_sha256=c0156954f3e048d56011524e0c2ae2881bb6db8173b53f9b2f4eb94197f02999
gsp_tu10x_sha256=d157e3b7dd5da2ca8d1ccb6ca98958f9e35d10a9ef7326277ebac133e4b0d1a7

depends="kmod"
makedepends="
	binutils
	elfutils
	gawk
	gcc
	make
"

# Build inputs supplied via the /input staging directory (same contract
# as saphira-zfs; signing key never lives in /recipes):
#   buildpkg nvidia-open /build/nv-input
#   <input>/linux-7.2.2/        pruned built kernel tree (kmod-ready)
#   <input>/saphira-module.pem  module signing key
#
# CUDA policy: the Saphira host stays pure musl. CUDA runs inside a
# version-matched glibc systemd-nspawn container; only these kmods and
# the matching GSP firmware belong on the host.
KVER=7.2.2

recipe_build()
{
	KDIR="$SRC/linux-$KVER"
	KEY="$SRC/saphira-module.pem"
	[ -f "$KDIR/Makefile" ] || { echo "ERROR: kernel build tree missing at $KDIR (staged /input?)" >&2; return 1; }
	[ -f "$KEY" ] || { echo "ERROR: module signing key missing at $KEY (staged /input?)" >&2; return 1; }
	[ -x "$KDIR/scripts/sign-file" ] || { echo "ERROR: $KDIR/scripts/sign-file not built" >&2; return 1; }

	NVBALL="$RECIPE_DIR/files/open-gpu-kernel-modules-610.57.04.tar.gz"
	echo "$nvidia_open_sha256  $NVBALL" | sha256sum -c -
	mkdir -p "$SRC/nvidia"
	tar --no-same-owner -C "$SRC/nvidia" --strip-components=1 -xf "$NVBALL"
	patch -d "$SRC/nvidia" -Np1 \
		-i "$RECIPE_DIR/files/0001-gate-fbdev-on-kconfig.patch"
	cd "$SRC/nvidia"

	make modules -j${JOBS:-$(nproc)} \
		SYSSRC="$KDIR" SYSOUT="$KDIR" \
		CC=gcc HOST_CC=gcc \
		IGNORE_CC_MISMATCH=1 \
		JOBS=${JOBS:-$(nproc)}

	for ko in kernel-open/*.ko; do
		"$KDIR/scripts/sign-file" sha256 "$KEY" "$KEY" "$ko"
	done
}

recipe_install()
{
	cd "$SRC/nvidia"
	install -d "$PKGDEST/lib/modules/$KVER/extra"
	for ko in kernel-open/nvidia.ko kernel-open/nvidia-modeset.ko \
		kernel-open/nvidia-drm.ko kernel-open/nvidia-uvm.ko; do
		[ -f "$ko" ] || { echo "ERROR: expected module missing: $ko" >&2; return 1; }
		install -m 0644 "$ko" "$PKGDEST/lib/modules/$KVER/extra/"
	done
	# GSP firmware path the module requests: nvidia/<NV_VERSION>/*.bin
	install -d "$PKGDEST/lib/firmware/nvidia/$pkgver"
	install -m 0644 "$RECIPE_DIR/files/gsp_ga10x.bin" \
		"$PKGDEST/lib/firmware/nvidia/$pkgver/gsp_ga10x.bin"
	install -m 0644 "$RECIPE_DIR/files/gsp_tu10x.bin" \
		"$PKGDEST/lib/firmware/nvidia/$pkgver/gsp_tu10x.bin"
	install -d "$PKGDEST/usr/share/doc/nvidia-open"
	cat > "$PKGDEST/usr/share/doc/nvidia-open/README.Saphira" <<'EOF'
NVIDIA open kernel modules 610.57.04 (host side only).

Load:
    depmod -a 7.2.2
    modprobe nvidia
    modprobe nvidia_uvm
    modprobe nvidia_modeset
    modprobe nvidia_drm     (optional; DRM/KMS)

/dev/nvidia* nodes appear only when real NVIDIA hardware is present
(a VM without GPU passthrough loads the modules but creates no nodes).

No CUDA userspace ships here by policy: run CUDA inside a glibc
systemd-nspawn container with NVIDIA userland of the SAME release
(610.57.04), binding /dev/nvidia* into the container. NVIDIA's
kernel/GSP/userspace version coupling is strict; do not mix releases.

Modules are signed with the Saphira module signing key.
EOF
}
