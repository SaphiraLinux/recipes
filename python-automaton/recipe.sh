#!/bin/sh

# python-automaton: Friendly state machines for Python.
#
# automaton 3.5.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-automaton
pkgver=3.5.0
pkgrel=1
pkgarch=noarch
pkgdesc="Friendly state machines for Python. (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=automaton
repo=saphira
url=https://pypi.org/project/automaton/
source=https://files.pythonhosted.org/packages/b6/5c/41826d34aa5c9278a8c55189ccc407737b2693bea7ecbf17ea8786619c7c/automaton-3.5.0.tar.gz
sha256=3896d03d328b52e341b7dd13c3e3963f0da44ac88a160ac07e761a087ddaa7e3

depends="
    python3
    python-prettytable
    typing-extensions"

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
