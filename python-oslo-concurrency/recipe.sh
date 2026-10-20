#!/bin/sh

# python-oslo-concurrency: oslo.concurrency: lockutils/processutils for OpenStack
#
# oslo.concurrency 7.6.1, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-oslo-concurrency
pkgver=7.6.1
pkgrel=1
pkgarch=noarch
pkgdesc="oslo.concurrency: lockutils/processutils for OpenStack"
license="Apache-2.0"
origin=oslo.concurrency
repo=saphira
url=https://pypi.org/project/oslo.concurrency/
source=https://files.pythonhosted.org/packages/90/d8/cd9a472611c8ce11c858195885c3e9383c054cca52e1f66ce287f6988d00/oslo_concurrency-7.6.1.tar.gz
sha256=8dcd3a6e931fc24d53832e887a124e3872e44e1af015cab47783bc67ad5b85e7

depends="
    python3
    python-fasteners
    python-oslo-config
    python-oslo-i18n
    python-oslo-utils
    python-debtcollector
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
