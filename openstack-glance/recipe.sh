#!/bin/sh
#
# openstack-glance: OpenStack Image service (Glance) 33.0.0 (2026.2 Hibiscus).
#
# The real image service: upstream executables (glance-api, glance-manage,
# glance-status, scrubber and cache tools), the WSGI application
# (glance.wsgi.api:application), alembic migrations and config templates,
# with dual-init (OpenRC + systemd) integration served by gunicorn.
#
# This package installs software ONLY. It does not enable or start any
# service, does not run glance-manage db_sync, and does not create
# credentials or a glance-api.conf. Applying those is an explicit
# operator action.
#
# Glance is independently installable: it depends on the python closure,
# a WSGI server and the keystone client libraries, never on Nova/Neutron
# or the rest of the suite.

pkgname=openstack-glance
pkgver=33.0.0
pkgrel=1
pkgarch=noarch
pkgdesc='OpenStack Image service (Glance): API, manage, scrubber, cache tools'
license='Apache-2.0'
origin=glance
repo=saphira
url=https://docs.openstack.org/glance/
source=https://files.pythonhosted.org/packages/5b/e6/a5393fd1d76dab6c45be28cc9fe2b3fd602e89ea50a8a1a144bc95e6f5c4/glance-33.0.0.tar.gz
sha256=f6483b580565836e412747ed247703e52a96b0cf168c732986ac595377c92678

depends="
	python3
	python-pbr
	python-defusedxml
	python-sqlalchemy
	python-pastedeploy
	python-routes
	python-webob
	python-alembic
	python-httplib2
	python-oslo-concurrency
	python-oslo-config
	python-oslo-context
	python-oslo-upgradecheck
	python-oslo-utils
	python-stevedore
	python-taskflow
	python-keystoneauth1
	python-keystonemiddleware
	python-keystoneclient
	python-wsme
	python-prettytable
	python-requests
	python-paste
	python-jsonschema
	python-oslo-db
	python-oslo-i18n
	python-oslo-limit
	python-oslo-log
	python-oslo-messaging
	python-oslo-middleware
	python-oslo-reports
	python-oslo-policy
	python-oslo-service
	python-osprofiler
	python-glance-store
	python-debtcollector
	python-cryptography
	python-cursive
	python-castellan
	python-gunicorn
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
		echo "ERROR: $SRC is not the extracted glance source" >&2
		return 1
	}
	# syntax-check the shipped init definitions
	sh -n "$RECIPE_DIR/files/glance.initd" || return 1
	sh -n "$RECIPE_DIR/files/glance.confd" || return 1
}

recipe_install()
{
	# The service itself: upstream python package, entry points and data
	# files (glance-* CLIs, WSGI app, alembic migrations, metadefs).
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

	# glance's pyproject declares [tool.setuptools.data-files]
	# "etc/glance" = [...]. The destination is prefix-relative, so pip
	# stages it at usr/etc/glance (a prefix-derived root makepkg
	# refuses). The intended config files are installed explicitly to
	# /etc/glance below, so drop the pip copy.
	rm -rf "$PKGDEST/usr/etc"

	# Wiring and templates. The generated *.conf files ship as *.sample:
	# no active glance-api.conf is ever installed (configuration is an
	# explicit operator step). The paste pipeline is upstream wiring,
	# useless without an operator-provided .conf.
	install -d -m 0755 "$PKGDEST/etc/glance/metadefs"
	install -m 0644 "$SRC/etc/glance-api-paste.ini" \
		"$PKGDEST/etc/glance/glance-api-paste.ini"
	for c in glance-api glance-cache glance-manage glance-scrubber; do
		install -m 0644 "$SRC/etc/$c.conf" \
			"$PKGDEST/etc/glance/$c.conf.sample"
	done
	install -m 0644 "$SRC/etc/glance-image-import.conf.sample" \
		"$PKGDEST/etc/glance/glance-image-import.conf.sample"
	install -m 0644 "$SRC/etc/glance-swift.conf.sample" \
		"$PKGDEST/etc/glance/glance-swift.conf.sample"
	install -m 0644 "$SRC/etc/property-protections-policies.conf.sample" \
		"$PKGDEST/etc/glance/property-protections-policies.conf.sample"
	install -m 0644 "$SRC/etc/property-protections-roles.conf.sample" \
		"$PKGDEST/etc/glance/property-protections-roles.conf.sample"
	install -m 0644 "$SRC/etc/schema-image.json" \
		"$PKGDEST/etc/glance/schema-image.json"
	install -m 0644 "$SRC/etc/metadefs/"*.json \
		"$PKGDEST/etc/glance/metadefs/"
	install -d -m 0755 "$PKGDEST/usr/share/glance"
	cp -r "$SRC/etc/oslo-config-generator" \
		"$PKGDEST/usr/share/glance/oslo-config-generator"

	# Dual-init service definitions (gunicorn + glance.wsgi.api:application).
	# Shipped unconditionally; neither is enabled or started at install.
	install -D -m 0755 "$RECIPE_DIR/files/glance.initd" \
		"$PKGDEST/etc/init.d/glance"
	install -D -m 0644 "$RECIPE_DIR/files/glance.confd" \
		"$PKGDEST/etc/conf.d/glance"
	install -D -m 0644 "$RECIPE_DIR/files/glance.service" \
		"$PKGDEST/usr/lib/systemd/system/glance.service"
	install -D -m 0644 "$RECIPE_DIR/files/glance.tmpfiles" \
		"$PKGDEST/usr/lib/tmpfiles.d/glance.conf"

	# Service identity (fragment basename must equal the package name;
	# the identity inside stays `glance`), FHS runtime dir and log
	# rotation fragments.
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/glance" \
		"$PKGDEST/usr/share/saphira/accounts.d/openstack-glance"
	install -D -m 0644 "$RECIPE_DIR/files/fhs.d/glance" \
		"$PKGDEST/usr/share/saphira/fhs.d/openstack-glance"
	install -D -m 0644 "$RECIPE_DIR/files/logrotate.d/glance" \
		"$PKGDEST/etc/logrotate.d/glance"

	install -D -m 0644 "$SRC/LICENSE" \
		"$PKGDEST/usr/share/licenses/openstack-glance/LICENSE"
	install -D -m 0644 "$RECIPE_DIR/files/README" \
		"$PKGDEST/usr/share/doc/openstack-glance/README"

	# Payload assertions: the software the operator expects must be present.
	for p in \
		usr/bin/glance-api \
		usr/bin/glance-manage \
		usr/bin/glance-status \
		usr/bin/glance-scrubber \
		usr/bin/glance-cache-manage \
		usr/bin/glance-cache-prefetcher \
		usr/bin/glance-cache-pruner \
		usr/bin/glance-cache-cleaner \
		usr/bin/glance-control \
		usr/bin/glance-replicator \
		usr/lib/python3.14/site-packages/glance/wsgi/api.py \
		usr/lib/python3.14/site-packages/glance/db/sqlalchemy/alembic_migrations \
		etc/glance/glance-api-paste.ini \
		etc/glance/glance-api.conf.sample \
		etc/glance/schema-image.json \
		etc/init.d/glance \
		etc/conf.d/glance \
		usr/lib/systemd/system/glance.service \
		usr/lib/tmpfiles.d/glance.conf \
		usr/share/saphira/accounts.d/openstack-glance \
		usr/share/saphira/fhs.d/openstack-glance \
		etc/logrotate.d/glance \
	; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: openstack-glance payload is missing $p" >&2
			return 1
		}
	done
	# This package must NOT pre-configure or auto-start anything.
	for c in glance-api glance-cache glance-manage glance-scrubber; do
		[ ! -e "$PKGDEST/etc/glance/$c.conf" ] || {
			echo "ERROR: openstack-glance must not ship $c.conf" >&2
			return 1
		}
	done
}
