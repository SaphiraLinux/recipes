#!/bin/sh

# python-jmespath: JSON Matching Expressions
#
# jmespath 1.1.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-jmespath
pkgver=1.1.0
pkgrel=1
pkgarch=noarch
pkgdesc="JSON Matching Expressions (OpenStack 2026.2 closure)"
license='MIT'
origin=jmespath
repo=saphira
url=https://pypi.org/project/jmespath/
source=https://files.pythonhosted.org/packages/d3/59/322338183ecda247fb5d1763a6cbe46eff7222eaeebafd9fa65d4bf5cb11/jmespath-1.1.0.tar.gz
sha256=472c87d80f36026ae83c6ddd0f1d05d4e510134ed462851fd5f754c8c3cbb88d

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
