#!/bin/sh
#
# openstack-horizon: OpenStack Dashboard (Horizon) 27.0.0 (2026.2 Hibiscus).
#
# The real web dashboard: the Django project openstack_dashboard plus
# openstack_auth, served by gunicorn
# (openstack_dashboard.wsgi:application), with static assets from the
# XStatic bundles, policy files and config samples.
#
# This package installs software ONLY. It does not enable or start any
# service, does not collect static assets, does not migrate the
# session database, and does not create local settings. Those are
# explicit operator actions.

pkgname=openstack-horizon
pkgver=27.0.0
pkgrel=2
pkgarch=noarch
pkgdesc='OpenStack Dashboard (Horizon): Django web UI'
license='Apache-2.0'
origin=horizon
repo=saphira
url=https://docs.openstack.org/horizon/
source=https://files.pythonhosted.org/packages/0c/9e/2bcfde737388940a9b45c98852e5d87ce37eac9f471bf8678be101ef533e/horizon-27.0.0.tar.gz
sha256=b1e16e3be554b543b1858df3b35dee3e4212e3ed61513512fddbe49584658cc0

depends="
	python3
	python-pbr
	python-babel
	python-django
	python-django-compressor
	python-django-debreach
	python-futurist
	python-iso8601
	python-keystoneauth1
	python-netaddr
	python-openstacksdk
	python-oslo-concurrency
	python-oslo-config
	python-oslo-i18n
	python-oslo-policy
	python-oslo-serialization
	python-oslo-upgradecheck
	python-oslo-utils
	python-osprofiler
	python-libsass
	python-pillow
	python-cinderclient
	python-glanceclient
	python-keystoneclient
	python-novaclient
	python-swiftclient
	pyyaml
	python-qrcode
	python-requests
	python-semantic-version
	python-xstatic
	python-xstatic-angular
	python-xstatic-angular-bootstrap
	python-xstatic-angular-fileupload
	python-xstatic-angular-gettext
	python-xstatic-angular-lrdragndrop
	python-xstatic-angular-schema-form
	python-xstatic-bootstrap-datepicker
	python-xstatic-bootstrap-scss
	python-xstatic-d3
	python-xstatic-font-awesome
	python-xstatic-hogan
	python-xstatic-jquery-migrate
	python-xstatic-jquery-tablesorter
	python-xstatic-jquery-quicksearch
	python-xstatic-jsencrypt
	python-xstatic-jasmine
	python-xstatic-rickshaw
	python-xstatic-spin
	python-xstatic-bootswatch
	python-xstatic-jquery
	python-xstatic-jquery-ui
	python-xstatic-mdi
	python-xstatic-objectpath
	python-xstatic-roboto-fontface
	python-xstatic-smart-table
	python-xstatic-term-js
	python-xstatic-tv4
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
		echo "ERROR: $SRC is not the extracted horizon source" >&2
		return 1
	}
	# syntax-check the shipped init definitions
	sh -n "$RECIPE_DIR/files/horizon.initd" || return 1
	sh -n "$RECIPE_DIR/files/horizon.confd" || return 1
}

recipe_install()
{
	# The dashboard itself: upstream Django project and auth backend.
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

	# Operator settings live outside site-packages so upgrades never
	# clobber them. /etc/horizon is on PYTHONPATH (see the units), so
	# `local.local_settings` resolves to the operator's file. Only the
	# example ships; an active local_settings.py is never installed.
	install -d -m 0755 "$PKGDEST/etc/horizon/local"
	: > "$PKGDEST/etc/horizon/local/__init__.py"
	chmod 0644 "$PKGDEST/etc/horizon/local/__init__.py"
	install -m 0644 "$SRC/openstack_dashboard/local/local_settings.py.example" \
		"$PKGDEST/etc/horizon/local/local_settings.py.example"
	# Saphira branding: replace the default navbar + splash artwork
	# with the files/branding SVGs (self-contained data-URI raster,
	# so no template changes are needed). Operators re-running
	# collectstatic pick this up automatically.
	install -m 0644 "$RECIPE_DIR/files/branding/logo.svg" \
		"$PKGDEST/usr/lib/python3.14/site-packages/openstack_dashboard/static/dashboard/img/logo.svg"
	install -m 0644 "$RECIPE_DIR/files/branding/logo-splash.svg" \
		"$PKGDEST/usr/lib/python3.14/site-packages/openstack_dashboard/static/dashboard/img/logo-splash.svg"
	# Policy samples for reference (the services ship their own
	# enforced copies; these document Horizon's view of them).
	install -d -m 0755 "$PKGDEST/usr/share/horizon"
	cp -r "$SRC/openstack_dashboard/conf" \
		"$PKGDEST/usr/share/horizon/conf"

	# Dual-init service definition (gunicorn + Django WSGI app).
	# Shipped unconditionally; neither enabled nor started at install.
	install -D -m 0755 "$RECIPE_DIR/files/horizon.initd" \
		"$PKGDEST/etc/init.d/horizon"
	install -D -m 0644 "$RECIPE_DIR/files/horizon.confd" \
		"$PKGDEST/etc/conf.d/horizon"
	install -D -m 0644 "$RECIPE_DIR/files/horizon.service" \
		"$PKGDEST/usr/lib/systemd/system/horizon.service"
	install -D -m 0644 "$RECIPE_DIR/files/horizon.tmpfiles" \
		"$PKGDEST/usr/lib/tmpfiles.d/horizon.conf"

	# Service identity (fragment basename must equal the package name;
	# the identity inside stays `horizon`), FHS runtime dir and log
	# rotation fragments.
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/horizon" \
		"$PKGDEST/usr/share/saphira/accounts.d/openstack-horizon"
	install -D -m 0644 "$RECIPE_DIR/files/fhs.d/horizon" \
		"$PKGDEST/usr/share/saphira/fhs.d/openstack-horizon"
	install -D -m 0644 "$RECIPE_DIR/files/logrotate.d/horizon" \
		"$PKGDEST/etc/logrotate.d/horizon"

	install -D -m 0644 "$SRC/LICENSE" \
		"$PKGDEST/usr/share/licenses/openstack-horizon/LICENSE"
	install -D -m 0644 "$RECIPE_DIR/files/README" \
		"$PKGDEST/usr/share/doc/openstack-horizon/README"

	# Payload assertions: the software the operator expects must be present.
	for p in \
		usr/lib/python3.14/site-packages/openstack_dashboard/wsgi.py \
		usr/lib/python3.14/site-packages/openstack_dashboard/settings.py \
		usr/lib/python3.14/site-packages/openstack_auth/user.py \
		etc/horizon/local/local_settings.py.example \
		etc/init.d/horizon \
		etc/conf.d/horizon \
		usr/lib/systemd/system/horizon.service \
		usr/lib/tmpfiles.d/horizon.conf \
		usr/share/saphira/accounts.d/openstack-horizon \
		usr/share/saphira/fhs.d/openstack-horizon \
		etc/logrotate.d/horizon \
		usr/lib/python3.14/site-packages/openstack_dashboard/static/dashboard/img/logo.svg \
		usr/lib/python3.14/site-packages/openstack_dashboard/static/dashboard/img/logo-splash.svg \
	; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: openstack-horizon payload is missing $p" >&2
			return 1
		}
	done
	# the shipped artwork must be Saphira's, not upstream's: both
	# branded SVGs carry a data-URI raster, upstream's carry paths.
	grep -q 'data:image/' \
		"$PKGDEST/usr/lib/python3.14/site-packages/openstack_dashboard/static/dashboard/img/logo.svg" || {
		echo "ERROR: openstack-horizon logo.svg is not the Saphira branding" >&2
		return 1
	}
	grep -q 'data:image/' \
		"$PKGDEST/usr/lib/python3.14/site-packages/openstack_dashboard/static/dashboard/img/logo-splash.svg" || {
		echo "ERROR: openstack-horizon logo-splash.svg is not the Saphira branding" >&2
		return 1
	}
	# This package must NOT pre-configure or auto-start anything: no
	# active local settings, ever.
	[ ! -e "$PKGDEST/etc/horizon/local/local_settings.py" ] || {
		echo "ERROR: openstack-horizon must not ship local_settings.py" >&2
		return 1
	}
}
