#!/bin/sh

# python-simplegeneric: Simple generic functions (similar to Python's own len(), pickle.dump(), etc.)
#
# simplegeneric 0.8.1, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-simplegeneric
pkgver=0.8.1
pkgrel=1
pkgarch=noarch
pkgdesc="Simple generic functions (similar to Python's own len(), pickle.dump(), etc.) (OpenStack 2026.2 closure)"
license='ZPL-2.1'
origin=simplegeneric
repo=saphira
url=https://pypi.org/project/simplegeneric/
source=https://files.pythonhosted.org/packages/3d/57/4d9c9e3ae9a255cd4e1106bb57e24056d3d0709fc01b2e3e345898e49d5b/simplegeneric-0.8.1.zip
sha256=dc972e06094b9af5b855b3df4a646395e43d1c9d0d39ed345b7393560d0b9173

depends="
    python3
"

makedepends="
    python3
    python3-pip
    setuptools
    wheel
    unzip
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
