#!/bin/sh

# python-networkx: Python package for creating and manipulating graphs and networks
#
# networkx 3.6.1, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-networkx
pkgver=3.6.1
pkgrel=1
pkgarch=noarch
pkgdesc="Python package for creating and manipulating graphs and networks (OpenStack 2026.2 closure)"
license='BSD-3-Clause'
origin=networkx
repo=saphira
url=https://pypi.org/project/networkx/
source=https://files.pythonhosted.org/packages/6a/51/63fe664f3908c97be9d2e4f1158eb633317598cfa6e1fc14af5383f17512/networkx-3.6.1.tar.gz
sha256=26b7c357accc0c8cde558ad486283728b65b6a95d85ee1cd66bafab4c8168509

depends="
    python3
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
