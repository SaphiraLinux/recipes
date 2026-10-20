#!/bin/sh

# python-keystoneclient: python-keystoneclient: OpenStack Identity (Keystone) client library and CLI
#
# python-keystoneclient 6.0.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-keystoneclient
pkgver=6.0.0
pkgrel=1
pkgarch=noarch
pkgdesc="python-keystoneclient: OpenStack Identity (Keystone) client library and CLI"
license="Apache-2.0"
origin=python-keystoneclient
repo=saphira
url=https://pypi.org/project/python-keystoneclient/
source=https://files.pythonhosted.org/packages/47/84/c24d6ec1b0a1c012b38fd00bc1699dacd998877ed6b28567249e5035ed47/python_keystoneclient-6.0.0.tar.gz
sha256=d6ac3a09adf2319aaac5728e3bf7cbeaf952c295bd7831f1df9a573b25fbcf82

depends="
    python3
    python-pbr
    python-debtcollector
    python-keystoneauth1
    python-oslo-config
    python-oslo-i18n
    python-oslo-serialization
    python-oslo-utils
    python-requests
    python-stevedore
    packaging
"
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
