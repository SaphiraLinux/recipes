#!/bin/sh
#
# saphira-openstack-controller: OpenStack controller-node role package.
#
# noarch, files-only metapackage: pulls the full controller closure
# (identity, image, placement, compute API, network API, dashboard and
# supporting infrastructure) and ships the interactive setup script
# that turns a bare Saphira machine into a working controller.
#
# The package installs software ONLY. Nothing is configured, enabled
# or started at install time. The operator (human or agent) runs
#   saphira-openstack-setup-controller
# once, answers a handful of questions, and gets a verified controller.
# Re-running the script is safe: it refuses to overwrite existing
# configuration unless given --force, and every phase verifies itself.

pkgname=saphira-openstack-controller
pkgver=0.1
pkgrel=1
pkgarch=noarch
pkgdesc='OpenStack controller role: services plus interactive setup (keystone, glance, placement, nova API, neutron API, horizon)'
license='BUSL-1.1'
origin=saphira-openstack-controller
repo=saphira
url=https://saphira.vm2.uk/

# Role closure: every service the controller runs, plus the
# infrastructure they stand on. The setup script configures them;
# the package manager provides them.
depends="
	mariadb
	rabbitmq-server
	memcached
	openstack-keystone
	openstack-glance
	openstack-placement
	openstack-nova
	openstack-neutron
	openstack-horizon
	saphira-openstack
"
makedepends=""

recipe_build()
{
	for f in "$RECIPE_DIR"/files/setup-controller; do
		sh -n "$f" || {
			echo "ERROR: $f does not parse" >&2
			return 1
		}
	done
}

recipe_install()
{
	install -d -m 0755 "$PKGDEST/usr/sbin" \
		"$PKGDEST/usr/share/doc/saphira-openstack-controller" \
		"$PKGDEST/usr/share/licenses/saphira-openstack-controller"

	install -m 0755 "$RECIPE_DIR/files/setup-controller" \
		"$PKGDEST/usr/sbin/saphira-openstack-setup-controller"
	install -m 0644 "$RECIPE_DIR/files/README" \
		"$PKGDEST/usr/share/doc/saphira-openstack-controller/README"
	install -m 0644 "$RECIPE_DIR/files/LICENSE" \
		"$PKGDEST/usr/share/licenses/saphira-openstack-controller/LICENSE"

	for p in \
		usr/sbin/saphira-openstack-setup-controller \
		usr/share/doc/saphira-openstack-controller/README \
		usr/share/licenses/saphira-openstack-controller/LICENSE \
	; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: saphira-openstack-controller payload is missing $p" >&2
			return 1
		}
	done
	# role package, not a daemon: no init units, no hooks
	[ ! -d "$PKGDEST/etc/init.d" ] || {
		echo "ERROR: saphira-openstack-controller must not ship init units" >&2
		return 1
	}
}
