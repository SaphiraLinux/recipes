#!/bin/sh

pkgname=package-template
pkgver=1.0.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Copy-me template for manually adding new packages under /recipes'
license='MIT'
origin=package-template
repo=saphira
url=https://packages.saphira.vm2.uk/

# To add a new package manually:
#   1. cp -r /recipes/package-template /recipes/<name>
#   2. Edit pkgname/pkgver/pkgdesc/license/url in recipe.sh.
#      url= must be non-empty (metadata contract) - use the package's
#      upstream project page, or https://saphira.vm2.uk/ for Saphira
#      originals.
#   3a. Upstream tarball: set source= and sha256= (worker downloads and
#       verifies); extract into $SRC in recipe_build.
#   3b. Local content: drop files under files/, pin them with sha256
#       before extraction; do NOT invent an upstream source= for vendored
#       payloads (see file/perl recipes for precedent).
#   4. Fill depends= (runtime) and makedepends= (build tools/-dev pkgs).
#   5. Implement recipe_build() + recipe_install(); $PKGDEST is the
#       staging root, $BUILDDIR is for out-of-tree builds.
#   6. Hand off to saphira-builder; create an MCP task to check the
#       build result later. Never run the build yourself.
#   7. Delete this comment block.
recipe_build()
{
	# Template payloads are not built; validate vendored content exists.
	test -f "$RECIPE_DIR/files/README.md"
}

recipe_install()
{
	install -D -m644 "$RECIPE_DIR/files/README.md" \
		"$PKGDEST/usr/share/doc/package-template/README.md"
}
