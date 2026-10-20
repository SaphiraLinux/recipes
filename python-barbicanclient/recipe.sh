#!/bin/sh

# python-barbicanclient: Client Library for OpenStack Barbican Key Management API
#
# python-barbicanclient 7.6.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-barbicanclient
pkgver=7.6.0
pkgrel=1
pkgarch=noarch
pkgdesc="Client Library for OpenStack Barbican Key Management API (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=python-barbicanclient
repo=saphira
url=https://pypi.org/project/python-barbicanclient/
source=https://files.pythonhosted.org/packages/d0/a5/db5f8c3f831155c7f44720ae917cbba23aab8a482790ffb221f4674fa3eb/python_barbicanclient-7.6.0.tar.gz
sha256=d2a79dfe49e0f7ab7412911b62147c7941dd9f9770323eb050a53c31b9322821

depends="
    python3
    python-cliff
    python-keystoneauth1
    python-oslo-i18n
    python-oslo-serialization
    python-oslo-utils
    python-pbr
    python-requests"

makedepends="
    python3
    python3-pip
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
