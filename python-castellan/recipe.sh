#!/bin/sh

# python-castellan: Generic Key Manager interface for OpenStack
#
# castellan 5.8.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-castellan
pkgver=5.8.0
pkgrel=1
pkgarch=noarch
pkgdesc="Generic Key Manager interface for OpenStack (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=castellan
repo=saphira
url=https://pypi.org/project/castellan/
source=https://files.pythonhosted.org/packages/41/0b/4cdb1a2cb2942d41fa7c995d32daaf4007c57fbd26b875d2c3c56ae191b1/castellan-5.8.0.tar.gz
sha256=f8629ce20964a429710b886a673611bd18c059eb3051b494f3662090f49a2ce2

depends="
    python3
    python-barbicanclient
    python-cryptography
    python-keystoneauth1
    python-oslo-config
    python-oslo-context
    python-oslo-i18n
    python-oslo-log
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
