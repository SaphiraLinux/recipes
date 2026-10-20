#!/bin/sh

# python-os-resource-classes: Resource Classes for OpenStack
#
# os-resource-classes 1.1.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-os-resource-classes
pkgver=1.1.0
pkgrel=1
pkgarch=noarch
pkgdesc="Resource Classes for OpenStack (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=os-resource-classes
repo=saphira
url=https://pypi.org/project/os-resource-classes/
source=https://files.pythonhosted.org/packages/44/81/0f05d5d149dbd20e7ca652b57a329b571c4b068a24df6edc65ca4cfc2e16/os-resource-classes-1.1.0.tar.gz
sha256=e0bcbb8961a9fe33b7213734c51c001812890e2be62101c9279c88b72f75f9eb

depends="
    python3
    python-pbr"

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
