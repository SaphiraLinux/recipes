#!/bin/sh

pkgname=fuse3
pkgver=3.18.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="FUSE userspace filesystem framework (libfuse3, mount helpers)"
license="LGPL-2.1-or-later AND GPL-2.0-or-later"
origin=fuse3
repo=main
url=https://github.com/libfuse/libfuse
# Provides libfuse3 for the glusterfs FUSE client plus the 99-fuse udev
# rule (KERNEL==fuse MODE=0666) that makes /dev/fuse usable. Saphira's
# udevdir is /lib/udev (systemd default, confirmed by udev.pc - no
# rootprefix override in the udev recipe). No suid bits (glusterd mounts
# as root; house no-special-bits precedent), no examples/tests, no
# initscript (pure library + helpers).
vendor=https://github.com/libfuse/libfuse/releases/download/fuse-3.18.2/fuse-3.18.2.tar.gz
sha256=f01de85717e20adf5f98aff324acd85dd73d61a5ca3834d573dcf0bd6e54a298

depends=""

subpackages="$pkgname-dev"

makedepends="
    gcc
    meson
    ninja
    pkgconf
"

recipe_build()
{
	# Local archive wins when present (verified, never re-downloaded);
	# otherwise build from the builder-verified $SOURCE_ARCHIVE (see
	# the gpsd recipe comment for why the re-extract is harmless).
	FUSEBALL="$RECIPE_DIR/files/fuse-3.18.2.tar.gz"
	if [ -f "$FUSEBALL" ]; then
		echo "$sha256  $FUSEBALL" | sha256sum -c -
	else
		[ -n "${SOURCE_ARCHIVE-}" ] && [ -f "$SOURCE_ARCHIVE" ] \
			|| { echo "ERROR: no local fuse-3.18.2.tar.gz and no fetched SOURCE_ARCHIVE" >&2; return 1; }
		FUSEBALL=$SOURCE_ARCHIVE
	fi
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$FUSEBALL"
	meson setup "$BUILDDIR" "$SRC" \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--buildtype=release \
		-Dexamples=false \
		-Dtests=false \
		-Duseroot=false \
		-Dinitscriptdir= \
		-Dudevrulesdir=/lib/udev/rules.d
	ninja -C "$BUILDDIR" -j${JOBS:-$(nproc)}
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C "$BUILDDIR" install
}
