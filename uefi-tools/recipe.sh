#!/bin/sh
pkgname=uefi-tools
# Upstream tags are lettered (A75); apk versions must start with a digit,
# so pkgver is the numeric release counter (A75 -> 75, monotonic).
pkgver=75
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='UEFI firmware image inspection (UEFIExtract, UEFIFind)'
license='BSD-2-Clause'
origin=uefi-tools
repo=saphira
url=https://github.com/LongSoft/UEFITool
# Current release tag at packaging time. The top-level meson build
# covers common/ plus the two CLI tools only; the Qt GUI under
# UEFITool/ is never entered, so no graphical stack can leak into the
# firmware-tools chain (a GUI package may come later, separately).
source=https://github.com/LongSoft/UEFITool/archive/refs/tags/A75.tar.gz
sha256=f624ac80cdd716ed5e071d46f1516c84ce99b44fd5ce72663903c0a569c40770

# Pure inspection tools: parse images, never modify. C++ tools need the
# compiler runtime (gcc-libs convention, never the full compiler).
depends="gcc-libs zlib"
makedepends="binutils gcc make meson ninja pkgconf zlib-dev"

recipe_build() {
	UEFI_BALL="$RECIPE_DIR/files/A75.tar.gz"
	echo "$sha256  $UEFI_BALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$UEFI_BALL"
	meson setup build "$SRC" \
		--prefix=/usr \
		-Dlibdir=lib
	meson compile -C build
}

recipe_install() {
	DESTDIR="$PKGDEST" meson install -C build
}
