#!/bin/sh

# python-swiftclient: OpenStack Object Storage API Client Library
#
# python-swiftclient 4.11.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-swiftclient
pkgver=4.11.0
pkgrel=1
pkgarch=noarch
pkgdesc="OpenStack Object Storage API Client Library (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=python-swiftclient
repo=saphira
url=https://pypi.org/project/python-swiftclient/
source=https://files.pythonhosted.org/packages/bf/91/631ff6c1f6420f8e5017e60d0e66246d1dd5b9a61a70038a198bab404416/python_swiftclient-4.11.0.tar.gz
sha256=9d96146f5c2948c08cbf221eecfc3b87f2f631f1995e5e5d6e1b800ea74233cc

depends="
    python3
    python-requests"

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
