#!/bin/sh

pkgname=ghostscript
pkgver=10.08.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="PostScript/PDF interpreter and renderer (headless: no X/CUPS/GTK)"
license='AGPL-3.0-or-later'
origin=ghostscript
repo=saphira
url=https://ghostscript.com/
source=https://github.com/ArtifexSoftware/ghostpdl-downloads/releases/download/gs10080/ghostpdl-10.08.0.tar.xz
sha256=94943e3c4adb7115d132b3c28b913672f2e62e6a9d802f7e754e716b1634174a

# NOTE: AGPL-3.0. Pillow and other consumers invoke `gs` as a separate
# process (no linking), so the AGPL's network clause does not propagate
# into them; the licence field states the upstream licence as-is.
# Server-side PDF conversion as a hosted service needs Artifex's
# commercial terms - see ghostscript.com/licensing. This is stated
# here so nobody deploys it unknowingly.
#
# Headless policy: no X11, no CUPS, no GTK, no D-Bus, no fontconfig,
# no libpaper. lcms2mt, libjpeg, libpng, freetype and expat have no
# system-lib switch upstream (local source is preferred deliberately,
# e.g. jpeg carries upstream's D_MAX_BLOCKS_IN_MCU hardening), so
# those compile bundled - documented here, not silent. System where
# switches exist: zlib, brotli (--without-local-*), libtiff is
# deliberately LOCAL: configure refuses mixing local libtiff with
# shared libjpeg, and shared libjpeg is unavailable (see above), so
# --with-system-libtiff would break the build. jbig2dec and openjpeg
# resolve to system libraries by auto-detection (no bundled source
# present); tesseract is off.
depends="
    zlib
    brotli
    jbig2dec
    openjpeg
"

makedepends="
    gcc
    make
    pkgconf
    zlib-dev
    brotli-dev
    jbig2dec-dev
    openjpeg-dev
"

subpackages="$pkgname-doc"
# No -dev split: the C API headers have no in-tree consumer; revisit
# if one appears rather than shipping a split nobody installs.

recipe_build()
{
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/ghostpdl-10.08.0.tar.xz"
	echo "$sha256  $RECIPE_DIR/files/ghostpdl-10.08.0.tar.xz" | sha256sum -c -
	cd "$SRC"
	./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
		--without-x \
		--disable-cups \
		--disable-dbus \
		--disable-gtk \
		--disable-fontconfig \
		--without-libpaper \
		--without-tesseract \
		--without-local-zlib \
		--without-local-brotli
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
	test -x "$PKGDEST/usr/bin/gs" || {
		echo "ERROR: staged payload is missing usr/bin/gs" >&2
		return 1
	}
	# AGPL licence text ships with the package (redistribution
	# obligations attach to this NVR; the text must travel with it).
	test -f "$SRC/LICENSE" || {
		echo "ERROR: upstream licence file missing from source tree" >&2
		return 1
	}
	install -D -m 0644 "$SRC/LICENSE" \
		"$PKGDEST/usr/share/licenses/ghostscript/LICENSE"
	# Bundled lcms2mt has no system-lib switch upstream, so it compiles
	# in: its own licence notice travels with it.
	test -f "$SRC/lcms2mt/COPYING" || {
		echo "ERROR: bundled lcms2mt licence missing from source tree" >&2
		return 1
	}
	install -D -m 0644 "$SRC/lcms2mt/COPYING" \
		"$PKGDEST/usr/share/licenses/ghostscript/COPYING.lcms2mt"
}
