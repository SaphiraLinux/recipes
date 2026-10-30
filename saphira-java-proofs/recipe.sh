#!/bin/sh

pkgname=saphira-java-proofs
pkgver=1.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="End-to-end OpenJDK proofs (sources, runnable JAR, install-time runtime smoke)"
license="BUSL-1.1"
origin=saphira-java-proofs
repo=main
url=https://saphira.vm2.uk/

# No vendored upstream: the sources are Saphira-owned files/ plus the
# JDK that compiles them. The BUILD is the compile test (javac runs
# in a consumer build root, exactly like Gradle will); the shipped
# JAR plus the install hook is the runtime proof (java -jar must
# print PROOF-OK wherever the package installs, daemon test root
# included). No daemon, no identity, no units, no network anywhere.
depends="
    openjdk17
"

makedepends="
    openjdk17
"

# Saphira-owned proof sources: javac + jar run here at build time
# with the exact commands proven live on Egg (HelloWorld, ProofApp
# with threads/crypto/resource, app.jar with Main-Class). Any step
# failing aborts the build loudly.
recipe_build()
{
	rm -rf "$BUILDDIR" && mkdir -p "$BUILDDIR"
	cp "$RECIPE_DIR"/files/HelloWorld.java "$RECIPE_DIR"/files/ProofApp.java \
		"$RECIPE_DIR"/files/proof.txt "$BUILDDIR"/
	cd "$BUILDDIR"
	javac HelloWorld.java ProofApp.java || return 1
	jar --create --file app.jar --main-class ProofApp \
		-C . ProofApp.class -C . proof.txt || return 1
	# Build-time runtime proof too: the repo JDK runs the
	# just-built JAR before anything ships.
	java -jar app.jar | grep -q PROOF-OK || return 1
}

recipe_install()
{
	mkdir -p "$PKGDEST/usr/share/java-proofs"
	install -m 0644 "$BUILDDIR"/HelloWorld.java "$BUILDDIR"/ProofApp.java \
		"$BUILDDIR"/proof.txt "$BUILDDIR"/app.jar \
		"$PKGDEST/usr/share/java-proofs/"
	install -D -m 0644 "$RECIPE_DIR/files/LICENSE" \
		"$PKGDEST/usr/share/licenses/saphira-java-proofs/LICENSE"
	install -d -m 0755 "$PKGDEST/usr/share/saphira/hooks.d/$pkgname"
	install -m 0755 "$RECIPE_DIR/files/hooks-smoke" \
		"$PKGDEST/usr/share/saphira/hooks.d/$pkgname/post-install"
	install -m 0755 "$RECIPE_DIR/files/hooks-smoke" \
		"$PKGDEST/usr/share/saphira/hooks.d/$pkgname/post-upgrade"
	# Payload proof: sources, runnable JAR, hook, license.
	for p in usr/share/java-proofs/HelloWorld.java \
		usr/share/java-proofs/ProofApp.java \
		usr/share/java-proofs/proof.txt \
		usr/share/java-proofs/app.jar \
		usr/share/saphira/hooks.d/saphira-java-proofs/post-install \
		usr/share/saphira/hooks.d/saphira-java-proofs/post-upgrade \
		usr/share/licenses/saphira-java-proofs/LICENSE; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: saphira-java-proofs payload is missing $p" >&2
			return 1
		}
	done
}
