#!/bin/sh
#
# openstack-placement: OpenStack Placement service 16.0.0 (2026.2 Hibiscus).
#
# The real resource-tracking service: upstream executables
# (placement-manage, placement-status), the WSGI application
# (placement.wsgi.api:application), alembic migrations and generator
# inputs, with dual-init (OpenRC + systemd) integration served by
# gunicorn.
#
# This package installs software ONLY. It does not enable or start any
# service, does not run placement-manage db_sync, and does not create
# credentials or a placement.conf. Applying those is an explicit
# operator action.
#
# Placement is independently installable: it depends on the python
# closure, a WSGI server and the keystone middleware libraries, never
# on Nova/Neutron or the rest of the suite.

pkgname=openstack-placement
pkgver=16.0.0
pkgrel=2
pkgarch=noarch
pkgdesc='OpenStack Placement service: resource tracking API'
license='Apache-2.0'
origin=openstack-placement
repo=saphira
url=https://docs.openstack.org/placement/
source=https://files.pythonhosted.org/packages/fc/3a/bf54d49894e020cc545ccc51faa0c72a96d6477ba2c2348f67c93be9c71f/openstack_placement-16.0.0.tar.gz
sha256=ec95a0f74a2be1326f91c377b46cf930838722235e39f741137f80bc7e59fb9c

depends="
	python3
	python-pbr
	python-sqlalchemy
	python-keystonemiddleware
	python-routes
	python-webob
	python-jsonschema
	python-requests
	python-oslo-concurrency
	python-oslo-config
	python-oslo-context
	python-oslo-log
	python-oslo-serialization
	python-oslo-utils
	python-oslo-db
	python-oslo-policy
	python-oslo-middleware
	python-oslo-upgradecheck
	python-os-resource-classes
	python-os-traits
	python-microversion-parse
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
		echo "ERROR: $SRC is not the extracted placement source" >&2
		return 1
	}
	# syntax-check the shipped init definitions
	sh -n "$RECIPE_DIR/files/placement.initd" || return 1
	sh -n "$RECIPE_DIR/files/placement.confd" || return 1
	# the argv sanitizer must at least compile (in-memory: the
	# recipe tree is mounted read-only, so py_compile's
	# __pycache__ write would fail the build)
	python3 -c "compile(open('$RECIPE_DIR/files/gunicorn.conf.py').read(), 'gunicorn.conf.py', 'exec')" || return 1
}

recipe_install()
{
	# The service itself: upstream python package, entry points and data
	# files (placement-manage, placement-status, WSGI app, migrations).
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

	# Defensive: drop any prefix-derived usr/etc copy should a future
	# upstream declare data-files (this release declares none).
	rm -rf "$PKGDEST/usr/etc"

	# The sdist ships no sample placement.conf or policy.yaml (they are
	# generated via tox; see the README). /etc/placement is created so
	# the operator has the canonical location; writing the configuration
	# itself is an explicit operator step.
	install -d -m 0755 "$PKGDEST/etc/placement"
	# Generator inputs: the operator renders placement.conf from these.
	install -d -m 0755 "$PKGDEST/usr/share/placement"
	install -m 0644 "$SRC/etc/placement/config-generator.conf" \
		"$PKGDEST/usr/share/placement/config-generator.conf"
	install -m 0644 "$SRC/etc/placement/policy-generator.conf" \
		"$PKGDEST/usr/share/placement/policy-generator.conf"

	# Dual-init service definitions (gunicorn + placement.wsgi.api:application).
	# Shipped unconditionally; neither is enabled or started at install.
	install -D -m 0755 "$RECIPE_DIR/files/placement.initd" \
		"$PKGDEST/etc/init.d/placement"
	install -D -m 0644 "$RECIPE_DIR/files/placement.confd" \
		"$PKGDEST/etc/conf.d/placement"
	install -D -m 0644 "$RECIPE_DIR/files/placement.service" \
		"$PKGDEST/usr/lib/systemd/system/placement.service"
	install -D -m 0644 "$RECIPE_DIR/files/placement.tmpfiles" \
		"$PKGDEST/usr/lib/tmpfiles.d/placement.conf"

	# Service identity (fragment basename must equal the package name;
	# the identity inside stays `placement`), FHS runtime dir and log
	# rotation fragments.
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/placement" \
		"$PKGDEST/usr/share/saphira/accounts.d/openstack-placement"
	install -D -m 0644 "$RECIPE_DIR/files/fhs.d/placement" \
		"$PKGDEST/usr/share/saphira/fhs.d/openstack-placement"
	install -D -m 0644 "$RECIPE_DIR/files/logrotate.d/placement" \
		"$PKGDEST/etc/logrotate.d/placement"
	# argv sanitizer for the gunicorn-served API (loaded via --config
	# by the units above).
	install -D -m 0644 "$RECIPE_DIR/files/gunicorn.conf.py" \
		"$PKGDEST/etc/placement/gunicorn.conf.py"

	install -D -m 0644 "$SRC/LICENSE" \
		"$PKGDEST/usr/share/licenses/openstack-placement/LICENSE"
	install -D -m 0644 "$RECIPE_DIR/files/README" \
		"$PKGDEST/usr/share/doc/openstack-placement/README"

	# Payload assertions: the software the operator expects must be present.
	for p in \
		usr/bin/placement-manage \
		usr/bin/placement-status \
		usr/lib/python3.14/site-packages/placement/wsgi/api.py \
		usr/lib/python3.14/site-packages/placement/db/sqlalchemy/alembic \
		usr/share/placement/config-generator.conf \
		usr/share/placement/policy-generator.conf \
		etc/placement/gunicorn.conf.py \
		etc/init.d/placement \
		etc/conf.d/placement \
		usr/lib/systemd/system/placement.service \
		usr/lib/tmpfiles.d/placement.conf \
		usr/share/saphira/accounts.d/openstack-placement \
		usr/share/saphira/fhs.d/openstack-placement \
		etc/logrotate.d/placement \
	; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: openstack-placement payload is missing $p" >&2
			return 1
		}
	done
	# This package must NOT pre-configure or auto-start anything.
	[ ! -e "$PKGDEST/etc/placement/placement.conf" ] || {
		echo "ERROR: openstack-placement must not ship a placement.conf" >&2
		return 1
	}
}
