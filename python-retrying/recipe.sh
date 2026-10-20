#!/bin/sh

# python-retrying: Retrying
#
# retrying 1.4.2, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-retrying
pkgver=1.4.2
pkgrel=1
pkgarch=noarch
pkgdesc="Retrying (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=retrying
repo=saphira
url=https://pypi.org/project/retrying/
source=https://files.pythonhosted.org/packages/c8/5a/b17e1e257d3e6f2e7758930e1256832c9ddd576f8631781e6a072914befa/retrying-1.4.2.tar.gz
sha256=d102e75d53d8d30b88562d45361d6c6c934da06fab31bd81c0420acb97a8ba39

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
