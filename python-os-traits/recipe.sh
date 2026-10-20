#!/bin/sh

# python-os-traits: A library containing standardized trait strings
#
# os-traits 3.9.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-os-traits
pkgver=3.9.0
pkgrel=1
pkgarch=noarch
pkgdesc="A library containing standardized trait strings (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=os-traits
repo=saphira
url=https://pypi.org/project/os-traits/
source=https://files.pythonhosted.org/packages/eb/54/68070c55d96437e5189e46f81781b8e5e7113f9bd0505480bc9c023bb7e1/os_traits-3.9.0.tar.gz
sha256=4c68ea8de3dc8088f4f87f382558291a0b1c679e63be796332611539fc11ff03

depends="
    python3
    python-pbr"

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
