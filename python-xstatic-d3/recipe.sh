#!/bin/sh

# python-xstatic-d3: D3 3.5.17 (XStatic packaging standard)
#
# XStatic-D3 3.5.17.1, vendored sdist, installed offline into system
# site-packages. Frontend asset bundle for Horizon; pure data.

pkgname=python-xstatic-d3
pkgver=3.5.17.1
pkgrel=1
pkgarch=noarch
pkgdesc="D3 3.5.17 (XStatic packaging standard) (OpenStack 2026.2 closure)"
license='MIT'
origin=XStatic-D3
repo=saphira
url=https://pypi.org/project/XStatic-D3/
source=https://files.pythonhosted.org/packages/a3/92/303467f930d33eb6925ecb5724dc6a65723813023cb751547cad3179842d/xstatic_d3-3.5.17.1.tar.gz
sha256=fba4a47c7eba0b7a3964cbe629423f405d1d44cfc77b9544dd4f0de36889b083

depends="
    python3
    python-xstatic
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
