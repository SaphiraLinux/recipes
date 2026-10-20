#!/bin/sh
#
# openstack-nova: OpenStack Compute service (Nova) 34.0.0 (2026.2 Hibiscus).
#
# The real compute service: upstream executables (nova-api served by
# gunicorn, conductor, scheduler, compute, the vnc/serial/spice console
# proxies, manage, status, policy, rootwrap), the WSGI application
# (nova.wsgi.osapi_compute:application), alembic migrations and config
# templates, with dual-init (OpenRC + systemd) integration.
#
# This package installs software ONLY. It does not enable or start any
# service, does not run nova-manage db syncs, and does not create
# credentials or a nova.conf. Applying those is an explicit operator
# action. Enable per node role: controller runs api/conductor/
# scheduler (and proxies as needed); compute nodes run nova-compute.
#
# Nova is independently installable: it depends on the python closure,
# a WSGI server, libvirt bindings and the database client libraries,
# never on Neutron/Cinder/Horizon or QEMU directly (libvirt fronts
# QEMU; the daemons talk to libvirtd, never to qemu binaries).
# The libvirt daemon package itself IS a dependency (r2+): the socket
# group it owns is nova-compute's only path to the daemons, and apk
# orders install accordingly (group exists before nova's supplementary
# membership reconciles).

pkgname=openstack-nova
pkgver=34.0.0
pkgrel=3
# r3: nova-api.service gains the missing NOVA_API_WORKERS default and
# moves EnvironmentFile last so operator conf.d overrides unit
# defaults (reverse order silently ignored operator BIND/CONF; empty
# WORKERS failed boot with gunicorn exit 2, proven on Hatchling).
# Unit change, revision bump.
# r2: nova joins the libvirt socket group (supplementary membership;
# polkit stays disabled, so the 0770 group sockets are nova-compute's
# only path to the daemons). Install-script change, revision bump.
pkgarch=noarch
pkgdesc='OpenStack Compute service (Nova): API, conductor, scheduler, compute, console proxies'
license='Apache-2.0'
origin=nova
repo=saphira
url=https://docs.openstack.org/nova/
source=https://files.pythonhosted.org/packages/ea/3f/ca2c220052802a26302a66a3584f757d4cbaaa1d1ce88f0f4e10fc0142a1/nova-34.0.0.tar.gz
sha256=919eef77cda4ce0cc4746a5853b5d9341ebd0ae37bc8b1939eb77d17727c00df

depends="
	python3
	python-pbr
	python-sqlalchemy
	python-decorator
	python-eventlet
	python-jinja2
	python-keystonemiddleware
	python-lxml
	python-routes
	python-cryptography
	python-webob
	python-greenlet
	python-pastedeploy
	python-paste
	python-prettytable
	python-alembic
	python-netaddr
	python-paramiko
	python-jsonschema
	python-cinderclient
	python-keystoneauth1
	python-neutronclient
	python-glanceclient
	python-requests
	python-stevedore
	python-websockify
	python-oslo-cache
	python-oslo-concurrency
	python-oslo-config
	python-oslo-context
	python-oslo-log
	python-oslo-limit
	python-oslo-reports
	python-oslo-serialization
	python-oslo-upgradecheck
	python-oslo-utils
	python-oslo-db
	python-oslo-rootwrap
	python-oslo-messaging
	python-oslo-policy
	python-oslo-privsep
	python-oslo-i18n
	python-oslo-service
	python-rfc3986
	python-oslo-middleware
	python-psutil
	python-oslo-versionedobjects
	python-os-brick
	python-os-resource-classes
	python-os-traits
	python-os-vif
	python-castellan
	python-microversion-parse
	python-tooz
	python-cursive
	python-retrying
	python-os-service-types
	python-dateutil
	python-futurist
	python-openstacksdk
	pyyaml
	python-gunicorn
	python-libvirt
	libvirt
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
		echo "ERROR: $SRC is not the extracted nova source" >&2
		return 1
	}
	# syntax-check the shipped init definitions
	for f in "$RECIPE_DIR"/files/nova-*.initd "$RECIPE_DIR"/files/nova-*.confd; do
		sh -n "$f" || return 1
	done
}

recipe_install()
{
	# The service itself: upstream python package, entry points and data
	# files (nova-* CLIs, WSGI app, migrations, rootwrap policy).
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

	# nova's pyproject declares [tool.setuptools.data-files]
	# "etc/nova" = [...]. The destination is prefix-relative, so pip
	# stages it at usr/etc/nova (a prefix-derived root makepkg
	# refuses). Rootwrap policy and wiring install explicitly to
	# /etc/nova below, so drop the pip copy.
	rm -rf "$PKGDEST/usr/etc"

	# Wiring and templates. api-paste.ini is upstream pipeline wiring,
	# useless without an operator-provided nova.conf. Rootwrap policy
	# (this package owns rootwrap.conf and rootwrap.d only) is
	# privilege-boundary config the compute service needs.
	install -d -m 0755 "$PKGDEST/etc/nova/rootwrap.d"
	install -m 0644 "$SRC/etc/nova/api-paste.ini" \
		"$PKGDEST/etc/nova/api-paste.ini"
	install -m 0644 "$SRC/etc/nova/rootwrap.conf" \
		"$PKGDEST/etc/nova/rootwrap.conf"
	install -m 0644 "$SRC/etc/nova/rootwrap.d/compute.filters" \
		"$PKGDEST/etc/nova/rootwrap.d/"
	install -m 0644 "$SRC/etc/nova/logging_sample.conf" \
		"$PKGDEST/etc/nova/logging_sample.conf"
	install -m 0644 "$SRC/etc/nova/release.sample" \
		"$PKGDEST/etc/nova/release.sample"
	install -d -m 0755 "$PKGDEST/usr/share/nova"
	install -m 0644 "$SRC/etc/nova/nova-config-generator.conf" \
		"$PKGDEST/usr/share/nova/nova-config-generator.conf"
	install -m 0644 "$SRC/etc/nova/nova-policy-generator.conf" \
		"$PKGDEST/usr/share/nova/nova-policy-generator.conf"

	# Dual-init service definitions. Shipped unconditionally; none is
	# enabled or started at install. The API is gunicorn-served; the
	# rest are standalone daemons reading /etc/nova/nova.conf.
	for svc in api conductor scheduler compute novncproxy serialproxy spicehtml5proxy; do
		install -D -m 0755 "$RECIPE_DIR/files/nova-$svc.initd" \
			"$PKGDEST/etc/init.d/nova-$svc"
		install -D -m 0644 "$RECIPE_DIR/files/nova-$svc.confd" \
			"$PKGDEST/etc/conf.d/nova-$svc"
		install -D -m 0644 "$RECIPE_DIR/files/nova-$svc.service" \
			"$PKGDEST/usr/lib/systemd/system/nova-$svc.service"
	done
	install -D -m 0644 "$RECIPE_DIR/files/nova.tmpfiles" \
		"$PKGDEST/usr/lib/tmpfiles.d/nova.conf"

	# Service identity (fragment basename must equal the package name;
	# the identity inside stays `nova`), FHS runtime dir and log
	# rotation fragments.
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/nova" \
		"$PKGDEST/usr/share/saphira/accounts.d/openstack-nova"
	install -D -m 0644 "$RECIPE_DIR/files/fhs.d/nova" \
		"$PKGDEST/usr/share/saphira/fhs.d/openstack-nova"
	install -D -m 0644 "$RECIPE_DIR/files/logrotate.d/nova" \
		"$PKGDEST/etc/logrotate.d/nova"

	install -D -m 0644 "$SRC/LICENSE" \
		"$PKGDEST/usr/share/licenses/openstack-nova/LICENSE"
	install -D -m 0644 "$RECIPE_DIR/files/README" \
		"$PKGDEST/usr/share/doc/openstack-nova/README"

	# Payload assertions: the software the operator expects must be present.
	for p in \
		usr/bin/nova-compute \
		usr/bin/nova-conductor \
		usr/bin/nova-manage \
		usr/bin/nova-novncproxy \
		usr/bin/nova-scheduler \
		usr/bin/nova-serialproxy \
		usr/bin/nova-spicehtml5proxy \
		usr/bin/nova-status \
		usr/lib/python3.14/site-packages/nova/wsgi/osapi_compute.py \
		usr/lib/python3.14/site-packages/nova/db/api/migrations \
		usr/lib/python3.14/site-packages/nova/db/main/migrations \
		etc/nova/api-paste.ini \
		etc/nova/rootwrap.conf \
		etc/nova/rootwrap.d/compute.filters \
		etc/init.d/nova-api \
		etc/init.d/nova-compute \
		etc/conf.d/nova-api \
		usr/lib/systemd/system/nova-api.service \
		usr/lib/systemd/system/nova-compute.service \
		usr/lib/tmpfiles.d/nova.conf \
		usr/share/saphira/accounts.d/openstack-nova \
		usr/share/saphira/fhs.d/openstack-nova \
		etc/logrotate.d/nova \
	; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: openstack-nova payload is missing $p" >&2
			return 1
		}
	done
	# This package must NOT pre-configure or auto-start anything.
	[ ! -e "$PKGDEST/etc/nova/nova.conf" ] || {
		echo "ERROR: openstack-nova must not ship a nova.conf" >&2
		return 1
	}
}
