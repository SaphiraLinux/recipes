#!/bin/sh

# python-pbr: pbr: Python Build Reasonableness
#
# pbr 7.0.3, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-pbr
pkgver=7.0.3
pkgrel=1
pkgarch=noarch
pkgdesc="pbr: Python Build Reasonableness"
license="Apache-2.0"
origin=pbr
repo=saphira
url=https://pypi.org/project/pbr/
source=https://files.pythonhosted.org/packages/5e/ab/1de9a4f730edde1bdbbc2b8d19f8fa326f036b4f18b2f72cfbea7dc53c26/pbr-7.0.3.tar.gz
sha256=b46004ec30a5324672683ec848aed9e8fc500b0d261d40a3229c2d2bbfcedc29

depends="
    python3
    setuptools
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
