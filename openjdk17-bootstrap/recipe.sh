#!/bin/sh

pkgname=openjdk17-bootstrap
pkgver=17.0.7_p5
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Musl-built OpenJDK 17 bootstrap seed (build-time only, never a runtime)'
license='GPL-2.0-only WITH Classpath-exception-2.0'
origin=openjdk17-bootstrap
repo=saphira
url=https://openjdk.org/
vendor=https://repo.chimera-linux.org/distfiles/openjdk-bootstrap-17.0.7_p5-x86_64.tar.xz
sha256=b0053f81d28e640ad96488d5b19d753a307643b7f7df0a5801cd0353eeb985bb

# Build-time seed only: the openjdk17 recipe consumes this via
# --with-boot-jdk at build time. Never a runtime dependency of
# anything shipped, never installed on hosts.
#
# Provenance (verified 2026-10-28, notes.db openjdk17 note 39):
# Chimera Linux musl-built bootstrap, bytes verified against their
# pinned x86_64 sha256 before vendoring. Upstream glibc binaries
# would need a compat layer Saphira does not ship; this seed keeps
# the whole JDK chain musl-native.
#
# Runtime closure, honestly stated: javac/jar and the other build
# tools load libjvm + libjava + libnio + libnet + libzip only. The
# image also carries GUI libraries (libawt, splashscreen) whose X11,
# ALSA and gif linkages have no Saphira provider by design (headless
# distribution) — they are never loaded by a build, same as in the
# Chimera bootstrap they came from. Declared depends cover what the
# build tools actually load: freetype (libfontmanager), fontconfig
# (font discovery) and libc++abi (libjvm links libc++.so.1, whose
# Egg copy DT_NEEDEDs the previously unpublished libc++abi.so.1 —
# proven dl failure, notes.db openjdk17 chain).
depends="
    fontconfig
    freetype
    libc++
    libc++abi
"

makedepends="
    binutils
"

subpackages=""

recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/openjdk-bootstrap-17.0.7_p5-x86_64.tar.xz" | sha256sum -c -
	mkdir -p "$SRC/seed"
	tar -xf "$RECIPE_DIR/files/openjdk-bootstrap-17.0.7_p5-x86_64.tar.xz" \
		-C "$SRC/seed" --strip-components=1
	# Demos never participate in a build; src.zip is documentation.
	rm -rf "$SRC/seed/demo"
	test -x "$SRC/seed/bin/javac" || {
		echo "ERROR: bootstrap seed has no bin/javac" >&2
		return 1
	}
}

recipe_install()
{
	mkdir -p "$PKGDEST/usr/lib/jvm/java-17-bootstrap"
	cp -a "$SRC/seed/." "$PKGDEST/usr/lib/jvm/java-17-bootstrap/"
	# Unique path, deliberately NOT java-17-openjdk: the real JDK
	# owns that name when it lands. No file conflicts by construction.
}
