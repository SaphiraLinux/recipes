#!/bin/sh

pkgname=saphira-mergetool
pkgver=0.1.0
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Resolve apk .apk-new upgrade artifacts: diff, accept, keep, or merge'
license='MIT'
origin=saphira-mergetool
repo=saphira
url=https://saphira.vm2.uk/

# Local recipe: the payload is authored in files/, not downloaded, so no
# upstream source/sha256 applies.
depends="python3"
makedepends=""
subpackages="$pkgname-doc"

recipe_build() {
	:
}

recipe_install() {
	install -d -m 0755 "$PKGDEST/usr/bin"
	install -m 0755 "$RECIPE_DIR/files/saphira-mergetool" \
		"$PKGDEST/usr/bin/saphira-mergetool"

	# Operator configuration (protected by apk's default +etc rule across
	# upgrades: local edits win, package changes land as .apk-new).
	install -d -m 0755 "$PKGDEST/etc/saphira"
	install -m 0644 "$RECIPE_DIR/files/mergetool.conf" \
		"$PKGDEST/etc/saphira/mergetool.conf"

	# README stays in main under /usr/share/saphira-mergetool (never
	# /usr/share/doc - that tree auto-splits to -doc and r1 shipped it
	# from main, so a move would collide with the published r1).
	install -d -m 0755 "$PKGDEST/usr/share/saphira-mergetool"
	install -m 0644 "$RECIPE_DIR/files/README.md" \
		"$PKGDEST/usr/share/saphira-mergetool/README.md"

	install -d -m 0755 "$PKGDEST/usr/share/man/man1"
	install -m 0644 "$RECIPE_DIR/files/saphira-mergetool.1" \
		"$PKGDEST/usr/share/man/man1/saphira-mergetool.1"
}
