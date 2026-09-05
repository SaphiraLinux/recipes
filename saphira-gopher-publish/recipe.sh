#!/bin/sh

pkgname=saphira-gopher-publish
pkgver=0.1.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Markdown to Gopher: walk a website and generate a geomyidae 0.99 Gopher tree'
license='MIT'
origin=saphira-gopher-publish
repo=saphira
url=https://saphira.vm2.uk/

# Runtime pair: python3 (stdlib-only publisher) and geomyidae (the Gopher
# server the generated tree is immediately useful with, providing
# /srv/gopher and the gopher account context).
depends="python3 geomyidae"
makedepends=""

# Local recipe: the payload is authored in files/, not downloaded, so no
# upstream source/sha256 applies.

recipe_build() {
	:;
}

recipe_install() {
	install -d -m 0755 "$PKGDEST/usr/bin"
	install -m 0755 "$RECIPE_DIR/files/saphira-gopher-publish" \
		"$PKGDEST/usr/bin/saphira-gopher-publish"

	# Operator configuration (protected by apk's default +etc rule across
	# upgrades: local edits win, package changes land as .apk-new).
	install -d -m 0755 "$PKGDEST/etc/saphira"
	install -m 0644 "$RECIPE_DIR/files/gopher-publisher.conf" \
		"$PKGDEST/etc/saphira/gopher-publisher.conf"

	# Seeded site content: the root menu include is site-owned and must
	# survive upgrades even when customised. apk's protected_paths.d is
	# the mechanism (apk-tools 3 honours +srv/gopher-source: modified
	# local files are never overwritten, package updates land as
	# .apk-new).
	install -d -m 0755 "$PKGDEST/etc/apk/protected_paths.d"
	install -m 0644 "$RECIPE_DIR/files/protected-paths" \
		"$PKGDEST/etc/apk/protected_paths.d/saphira-gopher-publish"
	install -d -m 0755 "$PKGDEST/srv/gopher-source"
	install -m 0644 "$RECIPE_DIR/files/root-menu.include" \
		"$PKGDEST/srv/gopher-source/root-menu.include"

	# Dual-init policy does not apply: publication is operator-driven
	# (no cron/timer by design for the first release).
	install -d -m 0755 "$PKGDEST/usr/share/doc/saphira-gopher-publish"
	install -m 0644 "$RECIPE_DIR/files/README.md" \
		"$PKGDEST/usr/share/doc/saphira-gopher-publish/README.md"
}
