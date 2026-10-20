#!/bin/sh

# python-pydot: Python interface to Graphviz's Dot
#
# pydot 4.0.1, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-pydot
pkgver=4.0.1
pkgrel=2
pkgarch=noarch
pkgdesc="Python interface to Graphviz's Dot (OpenStack 2026.2 closure)"
license='MIT'
origin=pydot
repo=saphira
url=https://pypi.org/project/pydot/
source=https://files.pythonhosted.org/packages/50/35/b17cb89ff865484c6a20ef46bf9d95a5f07328292578de0b295f4a6beec2/pydot-4.0.1.tar.gz
sha256=c2148f681c4a33e08bf0e26a9e5f8e4099a82e0e2a068098f32ce86577364ad5

depends="
    python3
    pyparsing"

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
