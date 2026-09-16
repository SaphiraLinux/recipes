#!/bin/sh

pkgname=nvidia-open-firmware
pkgver=610.57.04
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='NVIDIA open GPU GSP firmware 610.57.04 (shared by all nvidia-open-<kver> kmod packages)'
license="NVIDIA firmware license"
origin=nvidia-open
repo=saphira
url=https://github.com/NVIDIA/open-gpu-kernel-modules
# GSP firmware vendored from NVIDIA-Linux-x86_64-610.57.04.run (same
# release: NVIDIA kernel/userspace/GSP version coupling is strict).
gsp_ga10x_sha256=c0156954f3e048d56011524e0c2ae2881bb6db8173b53f9b2f4eb94197f02999
gsp_tu10x_sha256=d157e3b7dd5da2ca8d1ccb6ca98958f9e35d10a9ef7326277ebac133e4b0d1a7

# Handover from the retired monolithic nvidia-open (owned the firmware
# and doc paths): the file gate exempts retired names listed here.
replaces="nvidia-open"

recipe_build()
{
	echo "$gsp_ga10x_sha256  $RECIPE_DIR/files/gsp_ga10x.bin" | sha256sum -c -
	echo "$gsp_tu10x_sha256  $RECIPE_DIR/files/gsp_tu10x.bin" | sha256sum -c -
}

recipe_install()
{
	# GSP firmware path the module requests: nvidia/<NV_VERSION>/*.bin
	install -d "$PKGDEST/lib/firmware/nvidia/$pkgver"
	install -m 0644 "$RECIPE_DIR/files/gsp_ga10x.bin" \
		"$PKGDEST/lib/firmware/nvidia/$pkgver/gsp_ga10x.bin"
	install -m 0644 "$RECIPE_DIR/files/gsp_tu10x.bin" \
		"$PKGDEST/lib/firmware/nvidia/$pkgver/gsp_tu10x.bin"
	install -d "$PKGDEST/usr/share/doc/nvidia-open-firmware"
	cat > "$PKGDEST/usr/share/doc/nvidia-open-firmware/README.Saphira" <<'EOF'
NVIDIA open GPU GSP firmware 610.57.04 (host side only).

Shared by all nvidia-open-<kver> kernel module packages: install the
kmod package matching the running kernel alongside this firmware
package. NVIDIA kernel/GSP/userspace version coupling is strict; do
not mix releases.
EOF
}
