#!/bin/sh

# python-novaclient: Client library for OpenStack Compute API
#
# python-novaclient 18.13.1, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-novaclient
pkgver=18.13.1
pkgrel=1
pkgarch=noarch
pkgdesc="Client library for OpenStack Compute API (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=python-novaclient
repo=saphira
url=https://pypi.org/project/python-novaclient/
source=https://files.pythonhosted.org/packages/66/bc/df55eede807bf39c2fddf5ccd2700bcbc64b6e294caec05aa73a8d0ad175/python_novaclient-18.13.1.tar.gz
sha256=a9fe15f894ffb6b309ea5c282bd2c4bba929918c62736e6733a82ed915edd883

depends="
    python3
    python-iso8601
    python-keystoneauth1
    python-oslo-i18n
    python-oslo-serialization
    python-oslo-utils
    python-pbr
    python-prettytable
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
