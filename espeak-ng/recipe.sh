#!/bin/sh

# eSpeak NG 1.51: compact formant speech synthesizer.
#
# Headless-server shape: audio backends (pcaudiolib, sonic,
# mbrola, speechplayer consumers) are all opt-IN --with flags and
# stay off - Saphira ships no audio stack, and synthesis to WAV /
# stdout needs none of them. What this engine gives the console
# stack here: libespeak-ng for speech-dispatcher/brltty drivers,
# the espeak-ng CLI for file synthesis, and the voice data both
# consume. Playback on a headless host is files/pipes/remote, not
# a local sound card (documented, not a defect).
#
# Release tarball (self-contained, configure pregenerated): 1.51
# is used over 1.52.0 because the 1.52.0 release attaches no
# source asset (Android APK only). Caveat, learned the hard way:
# the 1.51 release tarball strips phsource/+dictsource/ (only 106
# files - the voice data cannot build from it), so this pins the
# annotated-tag git archive instead (same bytes as the release
# tag, full 1878-file data tree). The vendored filename follows
# the archive URL basename, per the vendor-pair rule. Git tree
# means autogen.sh first (no pregenerated configure).

pkgname=espeak-ng
pkgver=1.51
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Compact formant speech synthesizer and engine library"
license=GPL-3.0-or-later
origin=espeak-ng
repo=saphira
url=https://github.com/espeak-ng/espeak-ng
source=https://github.com/espeak-ng/espeak-ng/archive/refs/tags/1.51.tar.gz
sha256=f0e028f695a8241c4fa90df7a8c8c5d68dcadbdbc91e758a97e594bbb0a3bdbf

depends="
    musl
"
makedepends="
    autoconf
    automake
    binutils
    gcc
    libtool
    make
    pkgconf
"
subpackages="$pkgname-dev"

recipe_build()
{
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/1.51.tar.gz"
	echo "$sha256  $RECIPE_DIR/files/1.51.tar.gz" | sha256sum -c -
	cd "$SRC"
	./autogen.sh
	# --disable-static (no static archives ship) but rpath stays
	# ENABLED: the voice-data build step runs the just-linked
	# espeak-ng binary against its just-built .so, which only
	# resolves via the build-tree rpath libtool embeds in
	# uninstalled binaries. libtool relinks at install time
	# without it (/usr/lib is a default search path), so no
	# rpath leaks into the payload (asserted below).
	./configure --prefix=/usr \
		--disable-static
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
	test -f "$PKGDEST/usr/lib/libespeak-ng.so" ||
		{ echo "ERROR: libespeak-ng.so missing from payload" >&2; return 1; }
	test -x "$PKGDEST/usr/bin/espeak-ng" ||
		{ echo "ERROR: espeak-ng CLI missing from payload" >&2; return 1; }
	test -f "$PKGDEST/usr/share/espeak-ng-data/en_dict" ||
		{ echo "ERROR: voice data missing from payload" >&2; return 1; }
	# No build-tree rpath may leak into shipped binaries.
	if readelf -d "$PKGDEST/usr/bin/espeak-ng" | grep -qi 'rpath\|runpath'; then
		echo "ERROR: rpath leaked into installed espeak-ng" >&2; return 1; fi
}
