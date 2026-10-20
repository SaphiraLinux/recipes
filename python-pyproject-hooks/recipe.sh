#!/bin/sh

# python-pyproject-hooks: PEP 517 hook caller (python-build requirement)
#
# pyproject-hooks 1.3.3, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-pyproject-hooks
pkgver=1.3.3
pkgrel=1
pkgarch=noarch
pkgdesc="PEP 517 hook caller (OpenStack 2026.2 closure)"
license='MIT'
origin=pyproject-hooks
repo=saphira
url=https://pypi.org/project/pyproject-hooks/
source=https://files.pythonhosted.org/packages/6d/5d/f2ddeef4a855a102aaae5e97826a0260007522ab504421b75addfdb1517c/pyproject_hooks-1.3.3.tar.gz
sha256=defda19b854fa0d3bd4f76ea4ddcba8abd7dcfcdd585a6690ade050744fc5f43

depends="
    python3
"

makedepends="
    python3
    python3-pip
    python-flit-core
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
