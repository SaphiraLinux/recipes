#!/bin/sh

pkgname=gradle
pkgver=8.14.6
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Gradle build tool 8.14.x (AGP-compatible line; runs on the OpenJDK 17 runtime)'
license='Apache-2.0'
origin=gradle
repo=saphira
url=https://gradle.org/
vendor=https://services.gradle.org/distributions/gradle-8.14.6-bin.zip
sha256=7988ed071b2a07900e2ec715fca15c6ab72bce6db433af301fa7fa7e9407bd24

# Full JDK, deliberately: building needs javac, and every Gradle use
# here fetches dependencies over TLS — the JRE trust store is created
# by openjdk17's post-install hook, which only runs for the main
# package's own install. A JRE-only dep would leave HTTPS broken.
depends="
    openjdk17
"

makedepends="
    openjdk17
    unzip
"

# Upstream binary distribution (Apache-2.0, redistributable): the
# Gradle project ships this zip as its product, and building Gradle
# from source requires Gradle itself. Verified byte-identical against
# the published checksum before vendoring; the smoke test below runs
# the real binary.
recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/gradle-8.14.6-bin.zip" | sha256sum -c -
	rm -rf "$BUILDDIR" && mkdir -p "$BUILDDIR"
	unzip -q "$RECIPE_DIR/files/gradle-8.14.6-bin.zip" -d "$BUILDDIR"
	"$BUILDDIR"/gradle-8.14.6/bin/gradle --version | grep -q "Gradle 8.14.6" || {
		echo "ERROR: vendored Gradle does not identify as 8.14.6" >&2
		return 1
	}
}

recipe_install()
{
	mkdir -p "$PKGDEST/usr/share/gradle-8.14.6"
	cp -a "$BUILDDIR"/gradle-8.14.6/. "$PKGDEST/usr/share/gradle-8.14.6/"
	mkdir -p "$PKGDEST/usr/bin"
	ln -s ../share/gradle-8.14.6/bin/gradle "$PKGDEST/usr/bin/gradle"
	install -D -m 0644 "$BUILDDIR/gradle-8.14.6/LICENSE" \
		"$PKGDEST/usr/share/licenses/gradle/LICENSE"
}
