#!/bin/sh

# python-debtcollector: debtcollector: deprecation-warning helpers for OpenStack
#
# debtcollector 3.1.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-debtcollector
pkgver=3.1.0
pkgrel=1
pkgarch=noarch
pkgdesc="debtcollector: deprecation-warning helpers for OpenStack"
license="Apache-2.0"
origin=debtcollector
repo=saphira
url=https://pypi.org/project/debtcollector/
source=https://files.pythonhosted.org/packages/ad/57/1bbe02be744995408d944cf46b8c818cf072873064b1cd3c79c11618b216/debtcollector-3.1.0.tar.gz
sha256=278a45608cf16e79c0ae10851d869185c6b78f86610df8f27a451a18c1fec732

depends="
    python3
    python-wrapt
    python-pbr
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
