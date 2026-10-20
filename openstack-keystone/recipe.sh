#!/bin/sh
#
# openstack-keystone: OpenStack Identity (Keystone) 30.0.0 (2026.2 Hibiscus).
#
# The real identity service: upstream executables (keystone-manage,
# keystone-status), the WSGI application (keystone.wsgi.api:application),
# database migrations and config templates, with dual-init (OpenRC +
# systemd) integration served by gunicorn.
#
# This package installs software ONLY. It does not enable or start any
# service, does not run keystone-manage db_sync, and does not create
# credentials. Applying those is an explicit operator action.
#
# Keystone is independently installable: it depends on the python closure,
# a WSGI server and a database CLIENT, never on QEMU/Nova/Neutron or the
# rest of the suite.

pkgname=openstack-keystone
pkgver=30.0.0
pkgrel=1
pkgarch=noarch
pkgdesc='OpenStack Identity (Keystone) service: API, keystone-manage, migrations'
license='Apache-2.0'
origin=keystone
repo=saphira
url=https://docs.openstack.org/keystone/
source=https://files.pythonhosted.org/packages/ca/9d/c9bdd2f865d3c3c20e03ee017fed6ebfcb595df60861d78dc45a211f5384/keystone-30.0.0.tar.gz
sha256=8f3f77175a039e408d870c6ea697a4cc4e9cf2755bd6cbc11230db4146dd7df4

depends="
	python3
	python-pbr
	python-webob
	python-flask
	python-flask-restful
	python-werkzeug
	python-cryptography
	python-sqlalchemy
	python-stevedore
	python-keystoneclient
	python-keystonemiddleware
	python-bcrypt
	python-oslo-cache
	python-oslo-config
	python-oslo-context
	python-oslo-messaging
	python-oslo-db
	python-oslo-i18n
	python-oslo-log
	python-oslo-middleware
	python-oslo-policy
	python-oslo-serialization
	python-oslo-upgradecheck
	python-oslo-utils
	python-oauthlib
	python-pysaml2
	python-pyjwt
	python-dogpile-cache
	python-jsonschema
	python-pycadf
	python-msgpack
	python-osprofiler
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
		echo "ERROR: $SRC is not the extracted keystone source" >&2
		return 1
	}
	# syntax-check the shipped init definitions
	sh -n "$RECIPE_DIR/files/keystone.initd" || return 1
	sh -n "$RECIPE_DIR/files/keystone.confd" || return 1
}

recipe_install()
{
	# $SRC is the extracted keystone source: the worker verified the
	# vendored archive against sha256=, extracted it, and the build
	# function above asserted the tree is really keystone.

	# The service itself: upstream python package, entry points and data
	# files (keystone-manage, keystone-status, sso_callback_template.html).
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

	# keystone's pyproject declares [tool.setuptools.data-files]
	# "etc/keystone" = [etc/sso_callback_template.html]. The destination is
	# prefix-relative, so pip stages it at usr/etc/keystone (a
	# prefix-derived root makepkg refuses). The intended config files are
	# installed explicitly to /etc/keystone below, so drop the pip copy.
	rm -rf "$PKGDEST/usr/etc"

	# Config templates and the generator inputs. No keystone.conf is
	# written: configuration is an explicit operator step.
	install -d -m 0755 "$PKGDEST/etc/keystone"
	install -m 0644 "$SRC/etc/logging.conf.sample" \
		"$PKGDEST/etc/keystone/logging.conf.sample"
	install -m 0644 "$SRC/etc/sso_callback_template.html" \
		"$PKGDEST/etc/keystone/sso_callback_template.html"
	install -d -m 0755 "$PKGDEST/usr/share/keystone"
	install -m 0644 "$SRC/config-generator/keystone.conf" \
		"$PKGDEST/usr/share/keystone/keystone.conf"
	install -m 0644 "$SRC/config-generator/keystone-policy-generator.conf" \
		"$PKGDEST/usr/share/keystone/keystone-policy-generator.conf"

	# Dual-init service definitions (gunicorn + keystone.wsgi.api:application).
	# Shipped unconditionally; neither is enabled or started at install.
	install -D -m 0755 "$RECIPE_DIR/files/keystone.initd" \
		"$PKGDEST/etc/init.d/keystone"
	install -D -m 0644 "$RECIPE_DIR/files/keystone.confd" \
		"$PKGDEST/etc/conf.d/keystone"
	install -D -m 0644 "$RECIPE_DIR/files/keystone.service" \
		"$PKGDEST/usr/lib/systemd/system/keystone.service"
	install -D -m 0644 "$RECIPE_DIR/files/keystone.tmpfiles" \
		"$PKGDEST/usr/lib/tmpfiles.d/keystone.conf"

	# Service identity, FHS runtime dir and log rotation fragments.
	# fragment basenames must equal the package name (makepkg refuses
	# foreign fragments); the identity inside stays `keystone`.
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/keystone" \
		"$PKGDEST/usr/share/saphira/accounts.d/openstack-keystone"
	install -D -m 0644 "$RECIPE_DIR/files/fhs.d/keystone" \
		"$PKGDEST/usr/share/saphira/fhs.d/openstack-keystone"
	install -D -m 0644 "$RECIPE_DIR/files/logrotate.d/keystone" \
		"$PKGDEST/etc/logrotate.d/keystone"

	install -D -m 0644 "$SRC/LICENSE" \
		"$PKGDEST/usr/share/licenses/openstack-keystone/LICENSE"
	install -D -m 0644 "$RECIPE_DIR/files/README" \
		"$PKGDEST/usr/share/doc/openstack-keystone/README"

	# Payload assertions: the software the operator expects must be present.
	for p in \
		usr/bin/keystone-manage \
		usr/bin/keystone-status \
		usr/lib/python3.14/site-packages/keystone/wsgi/api.py \
		usr/lib/python3.14/site-packages/keystone/common/sql/migrations \
		etc/keystone/logging.conf.sample \
		etc/keystone/sso_callback_template.html \
		etc/init.d/keystone \
		etc/conf.d/keystone \
		usr/lib/systemd/system/keystone.service \
		usr/lib/tmpfiles.d/keystone.conf \
		usr/share/saphira/accounts.d/openstack-keystone \
		usr/share/saphira/fhs.d/openstack-keystone \
		etc/logrotate.d/keystone \
	; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: openstack-keystone payload is missing $p" >&2
			return 1
		}
	done
	# This package must NOT pre-configure or auto-start anything.
	[ ! -e "$PKGDEST/etc/keystone/keystone.conf" ] || {
		echo "ERROR: openstack-keystone must not ship a keystone.conf" >&2
		return 1
	}
}
