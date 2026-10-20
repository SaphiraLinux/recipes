#!/bin/sh

# python-semantic-version: A library implementing the 'SemVer' scheme.
#
# semantic-version 2.10.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-semantic-version
pkgver=2.10.0
pkgrel=1
pkgarch=noarch
pkgdesc="A library implementing the 'SemVer' scheme. (OpenStack 2026.2 closure)"
license='BSD-2-Clause'
origin=semantic-version
repo=saphira
url=https://pypi.org/project/semantic-version/
source=https://files.pythonhosted.org/packages/7d/31/f2289ce78b9b473d582568c234e104d2a342fd658cc288a7553d83bb8595/semantic_version-2.10.0.tar.gz
sha256=bdabb6d336998cbb378d4b9db3a4b56a1e3235701dc05ea2690d9a997ed5041c

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
