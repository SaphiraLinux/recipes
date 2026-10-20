#!/bin/sh

# python-cliff: Command Line Interface Formulation Framework
#
# cliff 4.16.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-cliff
pkgver=4.16.0
pkgrel=1
pkgarch=noarch
pkgdesc="Command Line Interface Formulation Framework (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=cliff
repo=saphira
url=https://pypi.org/project/cliff/
source=https://files.pythonhosted.org/packages/83/4a/908e0d2a7d81e3a199c24b8bf787670ba4ec15105785ff3834f1d4e16a84/cliff-4.16.0.tar.gz
sha256=85314ad49bd62f90a51094d4e31b1cb4d3b92fb83cb3935eeba0236c32839e75

depends="
    python3
    python-autopage
    python-cmd2
    python-prettytable
    python-stevedore
    pyyaml"

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
