#!/bin/sh

pkgname=saphirad-release
pkgver=0.2.1
pkgrel=1
# x86_64, not noarch: see saphira-base recipe.sh (repo has no
# noarch/ payload subdir yet; same fix applies here).
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='SaphiraD product identity: /etc/os-release for SaphiraD Linux 0.2.1 (systemd)'
license='BUSL-1.1'
origin=saphirad-release
repo=saphira
url=https://saphira.vm2.uk/

# Files-only recipe: the payload is maintained in this package tree.
# This package is what makes a running system know it is SaphiraD
# (systemd). The OpenRC twin is saphira-release; the two are never
# co-installed, and the image profile names exactly one of them, so
# the init choice is visible inside the system, not just in build data.
depends=""
# Mutual alternative with saphira-release: both packages own
# /etc/os-release (exactly one is ever installed; the profile names
# one), so each declares replaces on the other. Without this the
# repository ownership gate refuses the pair, correctly: one path,
# one owner, unless the takeover is declared.
replaces="saphira-release"
makedepends=""

recipe_build()
{
	:
}

recipe_install()
{
	install -D -m 0644 "$RECIPE_DIR/files/os-release" \
		"$PKGDEST/etc/os-release"
	install -D -m 0644 "$RECIPE_DIR/files/LICENSE" \
		"$PKGDEST/usr/share/licenses/saphirad-release/LICENSE"
	# /etc/os-release is the product contract: it must identify this
	# exact product and release, or the image gate fails closed.
	grep -q '^NAME="SaphiraD Linux"$' "$PKGDEST/etc/os-release" || {
		echo "ERROR: saphirad-release os-release does not identify SaphiraD Linux" >&2
		return 1
	}
	grep -q '^VERSION_ID=0.2.1$' "$PKGDEST/etc/os-release" || {
		echo "ERROR: saphirad-release os-release is not 0.2.1" >&2
		return 1
	}
}
