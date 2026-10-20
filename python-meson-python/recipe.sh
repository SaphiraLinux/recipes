#!/bin/sh

# python-meson-python: Meson PEP 517 build backend (numpy build requirement)
#
# meson-python 0.22.1, vendored sdist, installed offline into system
# site-packages. Pure python.

pkgname=python-meson-python
pkgver=0.22.1
pkgrel=1
pkgarch=noarch
pkgdesc="Meson PEP 517 build backend (OpenStack 2026.2 closure)"
license='MIT'
origin=meson-python
repo=saphira
url=https://pypi.org/project/meson-python/
source=https://files.pythonhosted.org/packages/b4/40/343ae23722d5d66a7b94b752d1b194202640995296379333b274b1860871/meson_python-0.22.1.tar.gz
sha256=52c88628b0e5671592dc2306613fb5f6f3615fd24def059b9894f143b7f9a139

depends="
    python3
    meson
    ninja
    packaging
    python-pyproject-metadata
"

# Under --no-build-isolation pip enforces build-system.requires
# from the environment: meson, packaging and pyproject-metadata must
# be pre-installed (the in-tree mesonpy backend itself needs only
# setuptools as the import shim).
makedepends="
    python3
    python3-pip
    setuptools
    wheel
    meson
    packaging
    python-pyproject-metadata
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
