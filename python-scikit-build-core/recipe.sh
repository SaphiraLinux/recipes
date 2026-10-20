#!/bin/sh

# python-scikit-build-core: CMake PEP 517 backend (pybind11/Pillow builds)
#
# scikit-build-core 1.1.1, vendored sdist, installed offline into system
# site-packages. Pure python (hatchling backend).

pkgname=python-scikit-build-core
pkgver=1.1.1
pkgrel=1
pkgarch=noarch
pkgdesc="CMake PEP 517 build backend (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=scikit-build-core
repo=saphira
url=https://pypi.org/project/scikit-build-core/
source=https://files.pythonhosted.org/packages/b2/1a/8c00b19c0a1e7acf890676af2efa430339d38e59fa9437f2aab8517af3f4/scikit_build_core-1.1.1.tar.gz
sha256=e347a59193c878ac56a363e57506938652a6dd8c965790cb1cbc6bc7e8d5abad

depends="
    python3
    packaging
    python-pathspec
"

makedepends="
    python3
    python3-pip
    python-hatchling
    python-hatch-vcs
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
