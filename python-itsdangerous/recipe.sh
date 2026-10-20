#!/bin/sh

# python-itsdangerous: itsdangerous: safe data serialization (Flask dependency)
#
# itsdangerous 2.2.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-itsdangerous
pkgver=2.2.0
pkgrel=1
pkgarch=noarch
pkgdesc="itsdangerous: safe data serialization (Flask dependency)"
license="BSD-3-Clause"
origin=itsdangerous
repo=saphira
url=https://pypi.org/project/itsdangerous/
source=https://files.pythonhosted.org/packages/9c/cb/8ac0172223afbccb63986cc25049b154ecfb5e85932587206f42317be31d/itsdangerous-2.2.0.tar.gz
sha256=e0050c0b7da1eea53ffaf149c0cfbb5c6e2e2b69c4bef22c81fa6eb73e5f6173

depends="
    python3
"
makedepends="
    python3
    python3-pip
    python-flit-core
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
