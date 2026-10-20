#!/bin/sh

# python-neutron-lib: Neutron shared routines and utilities
#
# neutron-lib 5.0.1, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-neutron-lib
pkgver=5.0.1
pkgrel=1
pkgarch=noarch
pkgdesc="Neutron shared routines and utilities (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=neutron-lib
repo=saphira
url=https://pypi.org/project/neutron-lib/
source=https://files.pythonhosted.org/packages/70/71/903875864a2fd8e0a3781c972684431de98ea40eff3a88a1c5afb10b567d/neutron_lib-5.0.1.tar.gz
sha256=76457d9d1423c7a0080e7243e0665c516f7be1988dc58d33d78e0468aab7205b

depends="
    python3
    python-debtcollector
    python-keystoneauth1
    python-netaddr
    python-os-ken
    python-os-traits
    python-oslo-concurrency
    python-oslo-config
    python-oslo-context
    python-oslo-db
    python-oslo-i18n
    python-oslo-log
    python-oslo-messaging
    python-oslo-policy
    python-oslo-serialization
    python-oslo-service
    python-oslo-utils
    python-oslo-versionedobjects
    python-osprofiler
    python-pbr
    python-pecan
    python-setproctitle
    python-sqlalchemy
    python-stevedore
    python-webob"

makedepends="
    python3
    python3-pip
    python-pbr
    setuptools
    wheel
"

recipe_build()
{
    :
}

recipe_install()
{
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
}
