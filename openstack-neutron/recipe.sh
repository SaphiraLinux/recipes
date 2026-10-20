#!/bin/sh
#
# openstack-neutron: OpenStack Networking (Neutron) 29.0.0 (2026.2 Hibiscus).
#
# The real network service: neutron-api served by gunicorn, the RPC
# server, and the OVS-path agents (openvswitch, dhcp, l3, metadata),
# with WSGI application (neutron.wsgi.api:application), alembic
# migrations and config templates, plus rootwrap policy, with
# dual-init (OpenRC + systemd) integration.
#
# This package installs software ONLY. It does not enable or start any
# service, does not run neutron-db-manage, and does not create
# credentials or a neutron.conf. Applying those is an explicit
# operator action. Enable per node role: controller/network nodes run
# the API and L3/DHCP/metadata agents; every hypervisor-adjacent node
# that carries tenant traffic runs the openvswitch agent.
#
# OVS scope: ML2/OVS mechanism driver with the native openvswitch
# daemons (ovs-vsctl/ovsdb). OVN is not packaged and not claimed.
# Legacy VRRP HA needs keepalived, which is not packaged: DVR and
# plain routing are unaffected. The L3/DHCP agents execute iptables
# and ipset at runtime (packaged alongside this service).

pkgname=openstack-neutron
pkgver=29.0.0
pkgrel=1
pkgarch=noarch
pkgdesc='OpenStack Networking service (Neutron): API, RPC, OVS/DHCP/L3/metadata agents'
license='Apache-2.0'
origin=neutron
repo=saphira
url=https://docs.openstack.org/neutron/
source=https://files.pythonhosted.org/packages/74/5a/99be86bcadfffd9f97ebc92524598c974b0eaeda505df8d9a494a1241e0c/neutron-29.0.0.tar.gz
sha256=4dc123ed085a4b2cc8af1c4fa8d7162042c4e7cfa5e895f62e99a3b46d92ba31

depends="
	python3
	python-pbr
	python-paste
	python-pastedeploy
	python-routes
	python-debtcollector
	python-decorator
	python-pecan
	python-httplib2
	python-requests
	python-jinja2
	python-keystonemiddleware
	python-netaddr
	python-neutron-lib
	python-tenacity
	python-sqlalchemy
	python-webob
	python-keystoneauth1
	python-alembic
	python-stevedore
	python-oslo-cache
	python-oslo-concurrency
	python-oslo-config
	python-oslo-context
	python-oslo-db
	python-oslo-i18n
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
	python-os-ken
	python-os-resource-classes
	python-ovs
	python-ovsdbapp
	python-psutil
	python-openssl
	python-novaclient
	python-openstacksdk
	python-designateclient
	python-os-vif
	python-futurist
	python-tooz
	python-gunicorn
	openvswitch
	dnsmasq
	iproute2
	iptables
	ipset
	conntrack-tools
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
		echo "ERROR: $SRC is not the extracted neutron source" >&2
		return 1
	}
	# syntax-check the shipped init definitions
	for f in "$RECIPE_DIR"/files/neutron-*.initd "$RECIPE_DIR"/files/neutron-*.confd; do
		sh -n "$f" || return 1
	done
}

recipe_install()
{
	# The service itself: upstream python package, entry points and data
	# files (neutron-* CLIs and agents, WSGI app, migrations, rootwrap).
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

	# neutron's pyproject declares [tool.setuptools.data-files]
	# "etc/neutron" = [...]. The destination is prefix-relative, so pip
	# stages it at usr/etc/neutron (a prefix-derived root makepkg
	# refuses). Rootwrap policy and wiring install explicitly to
	# /etc/neutron below, so drop the pip copy.
	rm -rf "$PKGDEST/usr/etc"

	# Wiring and templates. api-paste.ini is upstream pipeline wiring,
	# useless without an operator-provided neutron.conf. Rootwrap
	# policy (this package owns rootwrap.conf and rootwrap.d only) is
	# privilege-boundary config the agents need.
	install -d -m 0755 "$PKGDEST/etc/neutron/rootwrap.d"
	install -d -m 0755 "$PKGDEST/etc/neutron/plugins/ml2"
	install -m 0644 "$SRC/etc/neutron/api-paste.ini" \
		"$PKGDEST/etc/neutron/api-paste.ini"
	install -m 0644 "$SRC/etc/neutron/rootwrap.conf" \
		"$PKGDEST/etc/neutron/rootwrap.conf"
	install -m 0644 "$SRC/etc/neutron/rootwrap.d/"*.filters \
		"$PKGDEST/etc/neutron/rootwrap.d/"
	# 29.0.0 moved the sample configs out of etc/neutron/plugins;
	# the generator input is the source of the installed sample.
	install -m 0644 "$SRC/etc/oslo-config-generator/ml2_conf.ini" \
		"$PKGDEST/etc/neutron/plugins/ml2/ml2_conf.ini"
	install -d -m 0755 "$PKGDEST/usr/share/neutron"
	cp -r "$SRC/etc/oslo-config-generator" \
		"$PKGDEST/usr/share/neutron/oslo-config-generator"
	cp -r "$SRC/etc/oslo-policy-generator" \
		"$PKGDEST/usr/share/neutron/oslo-policy-generator"

	# Dual-init service definitions (API gunicorn-served; agents are
	# standalone daemons). Shipped unconditionally; none is enabled or
	# started at install.
	for svc in api rpc-server openvswitch-agent dhcp-agent l3-agent metadata-agent; do
		install -D -m 0755 "$RECIPE_DIR/files/neutron-$svc.initd" \
			"$PKGDEST/etc/init.d/neutron-$svc"
		install -D -m 0644 "$RECIPE_DIR/files/neutron-$svc.confd" \
			"$PKGDEST/etc/conf.d/neutron-$svc"
		install -D -m 0644 "$RECIPE_DIR/files/neutron-$svc.service" \
			"$PKGDEST/usr/lib/systemd/system/neutron-$svc.service"
	done
	install -D -m 0644 "$RECIPE_DIR/files/neutron.tmpfiles" \
		"$PKGDEST/usr/lib/tmpfiles.d/neutron.conf"

	# Service identity (fragment basename must equal the package name;
	# the identity inside stays `neutron`), FHS runtime dir and log
	# rotation fragments.
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/neutron" \
		"$PKGDEST/usr/share/saphira/accounts.d/openstack-neutron"
	install -D -m 0644 "$RECIPE_DIR/files/fhs.d/neutron" \
		"$PKGDEST/usr/share/saphira/fhs.d/openstack-neutron"
	install -D -m 0644 "$RECIPE_DIR/files/logrotate.d/neutron" \
		"$PKGDEST/etc/logrotate.d/neutron"

	install -D -m 0644 "$SRC/LICENSE" \
		"$PKGDEST/usr/share/licenses/openstack-neutron/LICENSE"
	install -D -m 0644 "$RECIPE_DIR/files/README" \
		"$PKGDEST/usr/share/doc/openstack-neutron/README"

	# Payload assertions: the software the operator expects must be present.
	for p in \
		usr/bin/neutron-openvswitch-agent \
		usr/bin/neutron-dhcp-agent \
		usr/bin/neutron-l3-agent \
		usr/bin/neutron-metadata-agent \
		usr/bin/neutron-rpc-server \
		usr/bin/neutron-db-manage \
		usr/bin/neutron-status \
		usr/lib/python3.14/site-packages/neutron/wsgi/api.py \
		usr/lib/python3.14/site-packages/neutron/db/migration/alembic_migrations \
		etc/neutron/api-paste.ini \
		etc/neutron/rootwrap.conf \
		etc/neutron/plugins/ml2/ml2_conf.ini \
		etc/init.d/neutron-api \
		etc/init.d/neutron-openvswitch-agent \
		etc/conf.d/neutron-api \
		usr/lib/systemd/system/neutron-api.service \
		usr/lib/systemd/system/neutron-openvswitch-agent.service \
		usr/lib/tmpfiles.d/neutron.conf \
		usr/share/saphira/accounts.d/openstack-neutron \
		usr/share/saphira/fhs.d/openstack-neutron \
		etc/logrotate.d/neutron \
	; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: openstack-neutron payload is missing $p" >&2
			return 1
		}
	done
	# This package must NOT pre-configure or auto-start anything.
	[ ! -e "$PKGDEST/etc/neutron/neutron.conf" ] || {
		echo "ERROR: openstack-neutron must not ship a neutron.conf" >&2
		return 1
	}
}
