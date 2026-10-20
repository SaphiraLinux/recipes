#!/bin/sh

# python-taskflow: Taskflow structured state management library.
#
# taskflow 6.4.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-taskflow
pkgver=6.4.0
pkgrel=1
pkgarch=noarch
pkgdesc="Taskflow structured state management library. (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=taskflow
repo=saphira
url=https://pypi.org/project/taskflow/
source=https://files.pythonhosted.org/packages/5b/d9/3501c0dee53b5e0a27844e87b8fee5f7f6a9e7e217e387d0bb45715ad110/taskflow-6.4.0.tar.gz
sha256=31a929b6f5df06e2e59f116215b93784ef6f6affce90ef55144362f2f35c6919

depends="
    python3
    python-automaton
    python-cachetools
    python-debtcollector
    python-fasteners
    python-futurist
    python-jsonschema
    python-networkx
    python-oslo-serialization
    python-oslo-utils
    python-pbr
    python-pydot
    python-stevedore
    python-tenacity"

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
