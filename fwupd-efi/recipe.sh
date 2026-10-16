#!/bin/sh
pkgname=fwupd-efi
pkgver=1.8
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='fwupd UEFI capsule EFI binaries (fwup*.efi)'
license='LGPL-2.1-or-later'
origin=fwupd-efi
repo=saphira
url=https://github.com/fwupd/fwupd-efi
source=https://github.com/fwupd/fwupd-efi/archive/refs/tags/1.8.tar.gz
sha256=c9f1f9b9b967ea50eb0b478f0d7693d6673d4cd76c8e7eb80c55fc44ec928925

# Freestanding EFI binaries via gnu-efi; no libc linkage by design.
# -Dgenpeimg=disabled: genpeimg (NX section flags for EFI binaries)
# is optional upstream, and its canonical source is gone (original
# vathpela repo 404s, no tags, no maintained fork found). NX support
# still lands via the python3-pefile fallback in generate_binary.py
# (python-pefile below, build-time only).
depends=""
makedepends="binutils gcc gnu-efi-dev make meson ninja pkgconf python3 python-pefile"

recipe_build() {
	case "${SAPHIRA_ARCH:-x86_64}" in
		x86_64|aarch64) ;;
		*) echo "ERROR: unsupported SAPHIRA_ARCH for fwupd-efi: ${SAPHIRA_ARCH:-x86_64}" >&2; return 1 ;;
	esac
	FWEFI_BALL="$RECIPE_DIR/files/${pkgver}.tar.gz"
	echo "$sha256  $FWEFI_BALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$FWEFI_BALL"
	meson setup build "$SRC" \
		--prefix=/usr \
		-Dlibdir=lib \
		-Dgenpeimg=disabled
	meson compile -C build
}

recipe_install() {
	DESTDIR="$PKGDEST" meson install -C build
}
