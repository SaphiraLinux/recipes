#!/bin/sh

# Self-documenting Saphira: the complete man hierarchy (saphira(7),
# recipe(5) canonical contract, tool and admin pages). No build step;
# pages install verbatim. saphira-build.8 lives here (moved from
# saphira-packager/files so the whole system has one review surface).

pkgname=saphira-docs
pkgver=1.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Saphira manual pages (tooling and recipe contract)"
license="BUSL-1.1"
origin=saphira-docs
repo=saphira
url=https://saphira.vm2.uk/

# Pages are data, but `man <page>` must work where docs land: pull
# the reader (man-db carries groff itself).
depends="man-db"
makedepends=""

recipe_build()
{
	:
}

recipe_install()
{
	for section in 1 5 7 8; do
		install -d "$PKGDEST/usr/share/man/man$section"
		for page in "$RECIPE_DIR/files/"*".$section"; do
			[ -e "$page" ] || continue
			install -m 0644 "$page" "$PKGDEST/usr/share/man/man$section/"
		done
	done
}
