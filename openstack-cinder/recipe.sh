#!/bin/sh
#
# openstack-cinder: OpenStack Block Storage (Cinder) 29.0.0 (2026.2 Hibiscus).
#
# The real block storage service: cinder-api served by gunicorn, the
# scheduler, volume and backup daemons, with WSGI application
# (cinder.wsgi.api:application), alembic migrations and config
# templates, plus rootwrap policy, with dual-init (OpenRC/systemd)
# integration.
#
# This package installs software ONLY. It does not enable or start any
# service, does not run cinder-manage db sync, and does not create
# credentials or a cinder.conf. Applying those is an explicit operator
# action. Enable per node role: controller runs api/scheduler (and
# backup); storage nodes run volume (and backup targets).
#
# Backend scope: the LVM, Ceph, NFS and ZFS drivers ship in the code;
# the operator provides the backing store (LVM tools, Ceph cluster,
# NFS share, or a ZFS pool via saphira-zfs-userspace). iSCSI export
# uses the kernel LIO target through rtslib-fb (targetcli is the
# optional interactive frontend, not required).

pkgname=openstack-cinder
pkgver=29.0.0
pkgrel=1
pkgarch=noarch
pkgdesc='OpenStack Block Storage service (Cinder): API, scheduler, volume, backup'
license='Apache-2.0'
origin=cinder
repo=saphira
url=https://docs.openstack.org/cinder/
source=https://files.pythonhosted.org/packages/1e/22/7669c01adcb5cad83a2e43c76ee13884d1fb102a1de98ef4029caa17b8b3/cinder-29.0.0.tar.gz
sha256=6372ca98db3d7781031ce5950b44698badd6176db794ff1f74b0621be583429e

depends="
	python3
	python-pbr
	python-decorator
	python-eventlet
	python-futurist
	python-greenlet
	python-iso8601
	python-jsonschema
	python-keystoneauth1
	python-keystonemiddleware
	python-lxml
	python-oslo-config
	python-oslo-concurrency
	python-oslo-context
	python-oslo-db
	python-oslo-log
	python-oslo-messaging
	python-oslo-middleware
	python-oslo-policy
	python-oslo-privsep
	python-oslo-reports
	python-oslo-rootwrap
	python-oslo-serialization
	python-oslo-service
	python-oslo-upgradecheck
	python-oslo-utils
	python-oslo-versionedobjects
	python-osprofiler
	packaging
	python-paramiko
	python-paste
	python-pastedeploy
	pyparsing
	python-barbicanclient
	python-glanceclient
	python-keystoneclient
	python-novaclient
	python-requests
	python-urllib3
	python-routes
	python-taskflow
	python-rtslib-fb
	python-sqlalchemy
	python-stevedore
	python-tabulate
	python-tenacity
	python-webob
	python-oslo-i18n
	python-oslo-vmware
	python-os-brick
	python-tooz
	python-castellan
	python-cryptography
	python-cursive
	zstd
	python-distro
	tzdata
	python-cachetools
	python-gunicorn
	saphira-zfs-userspace
"
makedepends="
	python3
	python3-pip
	python-pbr
	setuptools
	wheel
"

recipe_build()
{
	# buildpkg-single extracted the vendored archive into $SRC and
	# verified it against sha256= before running this function.
	[ -f "$SRC/pyproject.toml" ] || [ -f "$SRC/setup.py" ] || {
		echo "ERROR: $SRC is not the extracted cinder source" >&2
		return 1
	}
	# syntax-check the shipped init definitions
	for f in "$RECIPE_DIR"/files/cinder-*.initd "$RECIPE_DIR"/files/cinder-*.confd; do
		sh -n "$f" || return 1
	done
}

recipe_install()
{
	# The service itself: upstream python package, entry points and data
	# files (cinder-* CLIs and daemons, WSGI app, migrations, rootwrap).
	python3 -m pip install \
		--no-index \
		--no-deps \
		--ignore-installed \
		--no-build-isolation \
		--no-compile \
		--no-cache-dir \
		--root "$PKGDEST" \
		--prefix /usr \
		"$SRC"

	# cinder's pyproject declares [tool.setuptools.data-files]
	# etc/cinder + rootwrap.d. Destination is prefix-relative, so pip
	# stages it at usr/etc/cinder (a prefix-derived root makepkg
	# refuses). Policy and wiring install explicitly below, so drop
	# the pip copy.
	rm -rf "$PKGDEST/usr/etc"

	# Wiring and templates. api-paste.ini is upstream pipeline wiring,
	# useless without an operator-provided cinder.conf. Rootwrap
	# policy (this package owns rootwrap.conf and rootwrap.d only)
	# is privilege-boundary config the volume service needs.
	install -d -m 0755 "$PKGDEST/etc/cinder/rootwrap.d"
	install -m 0644 "$SRC/etc/cinder/api-paste.ini" \
		"$PKGDEST/etc/cinder/api-paste.ini"
	install -m 0644 "$SRC/etc/cinder/rootwrap.conf" \
		"$PKGDEST/etc/cinder/rootwrap.conf"
	install -m 0644 "$SRC/etc/cinder/rootwrap.d/volume.filters" \
		"$PKGDEST/etc/cinder/rootwrap.d/"
	install -m 0644 "$SRC/etc/cinder/logging_sample.conf" \
		"$PKGDEST/etc/cinder/logging_sample.conf"
	install -m 0644 "$SRC/etc/cinder/resource_filters.json" \
		"$PKGDEST/etc/cinder/resource_filters.json"
	install -d -m 0755 "$PKGDEST/usr/share/cinder"
	install -m 0644 "$SRC/tools/config/cinder-config-generator.conf" \
		"$PKGDEST/usr/share/cinder/cinder-config-generator.conf"
	install -m 0644 "$SRC/tools/config/cinder-policy-generator.conf" \
		"$PKGDEST/usr/share/cinder/cinder-policy-generator.conf"

	# Dual-init service definitions (API gunicorn-served; scheduler,
	# volume and backup are standalone daemons). Shipped unconditionally;
	# none is enabled or started at install.
	for svc in api scheduler volume backup; do
		install -D -m 0755 "$RECIPE_DIR/files/cinder-$svc.initd" \
			"$PKGDEST/etc/init.d/cinder-$svc"
		install -D -m 0644 "$RECIPE_DIR/files/cinder-$svc.confd" \
			"$PKGDEST/etc/conf.d/cinder-$svc"
		install -D -m 0644 "$RECIPE_DIR/files/cinder-$svc.service" \
			"$PKGDEST/usr/lib/systemd/system/cinder-$svc.service"
	done
	install -D -m 0644 "$RECIPE_DIR/files/cinder.tmpfiles" \
		"$PKGDEST/usr/lib/tmpfiles.d/cinder.conf"

	# Service identity (fragment basename must equal the package name;
	# the identity inside stays `cinder`), FHS runtime dir and log
	# rotation fragments.
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/cinder" \
		"$PKGDEST/usr/share/saphira/accounts.d/openstack-cinder"
	install -D -m 0644 "$RECIPE_DIR/files/fhs.d/cinder" \
		"$PKGDEST/usr/share/saphira/fhs.d/openstack-cinder"
	install -D -m 0644 "$RECIPE_DIR/files/logrotate.d/cinder" \
		"$PKGDEST/etc/logrotate.d/cinder"

	install -D -m 0644 "$SRC/LICENSE" \
		"$PKGDEST/usr/share/licenses/openstack-cinder/LICENSE"
	install -D -m 0644 "$RECIPE_DIR/files/README" \
		"$PKGDEST/usr/share/doc/openstack-cinder/README"

	# Payload assertions: the software the operator expects must be present.
	for p in \
		usr/bin/cinder-api \
		usr/bin/cinder-backup \
		usr/bin/cinder-manage \
		usr/bin/cinder-scheduler \
		usr/bin/cinder-status \
		usr/bin/cinder-volume \
		usr/bin/cinder-rtstool \
		usr/lib/python3.14/site-packages/cinder/wsgi/api.py \
		usr/lib/python3.14/site-packages/cinder/db/migrations/versions \
		etc/cinder/api-paste.ini \
		etc/cinder/rootwrap.conf \
		etc/cinder/rootwrap.d/volume.filters \
		etc/init.d/cinder-api \
		etc/init.d/cinder-volume \
		etc/conf.d/cinder-api \
		usr/lib/systemd/system/cinder-api.service \
		usr/lib/systemd/system/cinder-volume.service \
		usr/lib/tmpfiles.d/cinder.conf \
		usr/share/saphira/accounts.d/openstack-cinder \
		usr/share/saphira/fhs.d/openstack-cinder \
		etc/logrotate.d/cinder \
	; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: openstack-cinder payload is missing $p" >&2
			return 1
		}
	done
	# This package must NOT pre-configure or auto-start anything.
	[ ! -e "$PKGDEST/etc/cinder/cinder.conf" ] || {
		echo "ERROR: openstack-cinder must not ship a cinder.conf" >&2
		return 1
	}
}
