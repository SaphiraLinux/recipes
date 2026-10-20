#!/bin/sh

# python-designateclient: OpenStack DNS-as-a-Service - Client
#
# python-designateclient 7.0.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-designateclient
pkgver=7.0.0
pkgrel=1
pkgarch=noarch
pkgdesc="OpenStack DNS-as-a-Service - Client (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=python-designateclient
repo=saphira
url=https://pypi.org/project/python-designateclient/
source=https://files.pythonhosted.org/packages/92/66/9e39949850a7f086641508805ebeab1553451eabde353e05788288e3e80b/python_designateclient-7.0.0.tar.gz
sha256=d9a1086e7bf81f4034ca0ec7a243cbd8b344bfb6095e2903c553cc3807d2bed2

depends="
    python3
    python-cliff
    python-debtcollector
    python-jsonschema
    python-keystoneauth1
    python-osc-lib
    python-oslo-serialization
    python-oslo-utils
    python-pbr
    python-requests
    python-stevedore"

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
