#!/bin/sh

# python-cinderclient: OpenStack Block Storage API Client Library
#
# python-cinderclient 9.10.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-cinderclient
pkgver=9.10.0
pkgrel=1
pkgarch=noarch
pkgdesc="OpenStack Block Storage API Client Library (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=python-cinderclient
repo=saphira
url=https://pypi.org/project/python-cinderclient/
source=https://files.pythonhosted.org/packages/30/8d/6932c1f806acb081a5b8dd6798e489b027f17dad9c105bdf5e0d5121ab10/python_cinderclient-9.10.0.tar.gz
sha256=fb856e6f4382a4c84d82f00415e3c66514b73e12d94679935182ba4f86510916

depends="
    python3
    python-keystoneauth1
    python-oslo-i18n
    python-oslo-utils
    python-pbr
    python-prettytable
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
