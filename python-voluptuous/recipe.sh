#!/bin/sh

# python-voluptuous: Python data validation library
#
# voluptuous 0.16.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-voluptuous
pkgver=0.16.0
pkgrel=1
pkgarch=noarch
pkgdesc="Python data validation library (OpenStack 2026.2 closure)"
license='BSD-3-Clause'
origin=voluptuous
repo=saphira
url=https://pypi.org/project/voluptuous/
source=https://files.pythonhosted.org/packages/92/f4/0738e6849858deae22218be3bbb8207ba83a96e9d0ec7e8e8cd67b30e5ca/voluptuous-0.16.0.tar.gz
sha256=006535e22fed944aec17bef6e8725472476194743c87bd233e912eb463f8ff05

depends="
    python3
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
