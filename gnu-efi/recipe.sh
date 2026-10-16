#!/bin/sh
pkgname=gnu-efi
pkgver=4.0.4
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='UEFI development headers and libraries (fwupd-efi dependency)'
license='GPL-2.0-or-later OR BSD-3-Clause'
origin=gnu-efi
repo=saphira
url=https://github.com/ncroxon/gnu-efi
# Maintained canonical home of gnu-efi (was SourceForge). Freestanding
# EFI code (own crt0, -nostdlib): musl/glibc-independent by design.
# x86_64 and aarch64 both supported upstream; ARCH follows the
# compiler dumpmachine (SAPHIRA_ARCH case fails closed otherwise).
source=https://github.com/ncroxon/gnu-efi/archive/refs/tags/4.0.4.tar.gz
sha256=40b61e842a4efcbf80f3e53b2f220c044e8cfe46eb4dd6396c83b751240b1c0d

depends=""
makedepends="binutils gcc make"
subpackages="$pkgname-dev"

recipe_build() {
	case "${SAPHIRA_ARCH:-x86_64}" in
		x86_64|aarch64) ;;
		*) echo "ERROR: unsupported SAPHIRA_ARCH for gnu-efi: ${SAPHIRA_ARCH:-x86_64}" >&2; return 1 ;;
	esac
	# Tag tarball vendored under URL basename.
	EFI_BALL="$RECIPE_DIR/files/${pkgver}.tar.gz"
	echo "$sha256  $EFI_BALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$EFI_BALL"
	make -C "$SRC" -j${JOBS:-$(nproc)} CC=gcc
}

recipe_install() {
	make -C "$SRC" PREFIX=/usr LIBDIR=/usr/lib INSTALLROOT="$PKGDEST" install
}
