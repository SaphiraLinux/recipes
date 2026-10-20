#!/bin/sh

# python-pybind11: seamless C++/Python bindings (Pillow build requirement)
#
# pybind11 3.1.0, vendored sdist, installed offline into system
# site-packages. Header-only; the scikit-build-core backend drives it.

pkgname=python-pybind11
pkgver=3.1.0
pkgrel=1
pkgarch=noarch
pkgdesc="seamless C++/Python bindings (OpenStack 2026.2 closure)"
license='BSD-3-Clause'
origin=pybind11
repo=saphira
url=https://pypi.org/project/pybind11/
source=https://files.pythonhosted.org/packages/76/f3/95b0f40b31df41dbfe6bb0857419c9442c15839cbac4796f1c26ae0b6081/pybind11-3.1.0.tar.gz
sha256=a1cc06b524ab3edca51f8ad3895f9c4fa20b8b19283173dff4ae781449dc9639

depends="
    python3
"

makedepends="
    python3
    python3-pip
    python-scikit-build-core
    cmake
    ninja
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
