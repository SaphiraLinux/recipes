#!/bin/sh

# python-pyjwt: PyJWT: JSON Web Token implementation (keystonemiddleware)
#
# PyJWT 2.13.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-pyjwt
pkgver=2.13.0
pkgrel=1
pkgarch=noarch
pkgdesc="PyJWT: JSON Web Token implementation (keystonemiddleware)"
license="MIT"
origin=PyJWT
repo=saphira
url=https://pypi.org/project/PyJWT/
source=https://files.pythonhosted.org/packages/3b/81/58d0ac84e1ef3a3843791d6954d94c0b33d526c75eeb1efbce9d0a4c4077/pyjwt-2.13.0.tar.gz
sha256=41571c89ca91598c79e8ef18a2d07367d4810fbbd6f637794879baf1b7703423

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
