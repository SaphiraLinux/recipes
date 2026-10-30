#!/bin/sh

pkgname=alsa-lib
pkgver=1.2.16.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Advanced Linux Sound Architecture library (libasound, headers, config)"
license="LGPL-2.1-only"
origin=alsa-lib
repo=main
url=https://www.alsa-project.org/
vendor=https://www.alsa-project.org/files/pub/lib/alsa-lib-1.2.16.1.tar.bz2
sha256=f740db7f488255944ffd4428416ee3390a96742856916433df468c281436480e

# libasound for the JDK sound engine (libjsound links -lasound;
# NEEDS_LIB_ALSA is true on every Linux target and --with-alsa=no
# is refused, so this port is mandatory, not optional). Library
# only: no daemon, no identity, no units. alsa-utils stay unpackaged
# (no consumer: nothing in the tree runs speaker-test/aplay).
depends="
"

makedepends="
    binutils
    gcc
    make
"

subpackages="
    $pkgname-dev
    $pkgname-doc
"

# Plain autotools C library, self-contained (no required deps).
# Upstream defaults kept: full mixer/PCM topology including the
# /usr/share/alsa configuration tree (cards, pcm presets) that
# libasound reads at runtime. Nothing disabled.
recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/alsa-lib-1.2.16.1.tar.bz2" | sha256sum -c -
	rm -rf "$BUILDDIR" && mkdir -p "$BUILDDIR"
	tar --no-same-owner -xf "$RECIPE_DIR/files/alsa-lib-1.2.16.1.tar.bz2" \
		-C "$BUILDDIR" --strip-components=1
	cd "$BUILDDIR"
	# layout baseline: --prefix=/usr --sysconfdir=/etc
	# --localstatedir=/var (explicit, never inherited).
	./configure \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var
	make
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
	# Payload proof: the runtime object, the headers (auto -dev
	# split) and the configuration tree libasound requires.
	for p in usr/lib/libasound.so \
		usr/include/alsa/asoundlib.h \
		usr/share/alsa/alsa.conf; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: alsa-lib payload is missing $p" >&2
			return 1
		}
	done
}
