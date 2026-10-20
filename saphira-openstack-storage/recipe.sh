#!/bin/sh
#
# saphira-openstack-storage: OpenStack storage-node (cinder) role.
#
# noarch, files-only metapackage: pulls the storage closure (cinder,
# LVM tooling) and ships the interactive setup script that prepares a
# bare Saphira machine as a cinder LVM volume host.
#
# The package installs software ONLY. Nothing is configured, enabled
# or started at install time. The operator runs
#   saphira-openstack-setup-storage
# which prepares everything up to the iSCSI target gate and says
# plainly what is still missing. Re-running is safe.

pkgname=saphira-openstack-storage
pkgver=0.1
pkgrel=1
pkgarch=noarch
pkgdesc='OpenStack storage role: cinder LVM host prep plus interactive setup (iSCSI target pending)'
license='BUSL-1.1'
origin=saphira-openstack-storage
repo=saphira
url=https://saphira.vm2.uk/

depends="
	openstack-cinder
	lvm2
	saphira-openstack
"
makedepends=""

recipe_build()
{
	for f in "$RECIPE_DIR"/files/setup-storage; do
		sh -n "$f" || {
			echo "ERROR: $f does not parse" >&2
			return 1
		}
	done
}

recipe_install()
{
	install -d -m 0755 "$PKGDEST/usr/sbin" \
		"$PKGDEST/usr/share/doc/saphira-openstack-storage" \
		"$PKGDEST/usr/share/licenses/saphira-openstack-storage"

	install -m 0755 "$RECIPE_DIR/files/setup-storage" \
		"$PKGDEST/usr/sbin/saphira-openstack-setup-storage"
	install -m 0644 "$RECIPE_DIR/files/README" \
		"$PKGDEST/usr/share/doc/saphira-openstack-storage/README"
	install -m 0644 "$RECIPE_DIR/files/LICENSE" \
		"$PKGDEST/usr/share/licenses/saphira-openstack-storage/LICENSE"

	for p in \
		usr/sbin/saphira-openstack-setup-storage \
		usr/share/doc/saphira-openstack-storage/README \
		usr/share/licenses/saphira-openstack-storage/LICENSE \
	; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: saphira-openstack-storage payload is missing $p" >&2
			return 1
		}
	done
	[ ! -d "$PKGDEST/etc/init.d" ] || {
		echo "ERROR: saphira-openstack-storage must not ship init units" >&2
		return 1
	}
}
