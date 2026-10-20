#!/bin/sh
#
# saphira-openstack-documentation: the OpenStack books.
#
# noarch, files-only package: how-to guides for each node role plus
# the pitfalls guide, written from the actual first bring-up. No
# theory, no copy-paste from upstream docs that assume Ubuntu and an
# openstack CLI: every command here ran on Saphira, against these
# exact packages, with curl as the only client.
#
# Installs text ONLY. Configures nothing, starts nothing.

pkgname=saphira-openstack-documentation
pkgver=0.1
pkgrel=1
pkgarch=noarch
pkgdesc='OpenStack on Saphira: per-role how-to guides plus the pitfalls book'
license='BUSL-1.1'
origin=saphira-openstack-documentation
repo=saphira
url=https://saphira.vm2.uk/

depends=""
makedepends=""

recipe_build()
{
	# every guide referenced by the index must exist and be non-empty
	for f in controller compute storage pitfalls; do
		[ -s "$RECIPE_DIR/files/openstack-$f.txt" ] || {
			echo "ERROR: guide openstack-$f.txt is missing or empty" >&2
			return 1
		}
	done
}

recipe_install()
{
	install -d -m 0755 "$PKGDEST/usr/share/doc/saphira-openstack-documentation" \
		"$PKGDEST/usr/share/licenses/saphira-openstack-documentation"

	for f in README controller compute storage pitfalls; do
		case $f in
			README) src=README ;;
			*) src=openstack-$f.txt ;;
		esac
		install -m 0644 "$RECIPE_DIR/files/$src" \
			"$PKGDEST/usr/share/doc/saphira-openstack-documentation/$src"
	done
	install -m 0644 "$RECIPE_DIR/files/LICENSE" \
		"$PKGDEST/usr/share/licenses/saphira-openstack-documentation/LICENSE"

	for p in \
		usr/share/doc/saphira-openstack-documentation/README \
		usr/share/doc/saphira-openstack-documentation/openstack-controller.txt \
		usr/share/doc/saphira-openstack-documentation/openstack-compute.txt \
		usr/share/doc/saphira-openstack-documentation/openstack-storage.txt \
		usr/share/doc/saphira-openstack-documentation/openstack-pitfalls.txt \
		usr/share/licenses/saphira-openstack-documentation/LICENSE \
	; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: saphira-openstack-documentation payload is missing $p" >&2
			return 1
		}
	done
}
