#!/bin/sh

# python-paramiko: SSH2 protocol library
#
# paramiko 4.0.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-paramiko
pkgver=4.0.0
pkgrel=1
pkgarch=noarch
pkgdesc="SSH2 protocol library (OpenStack 2026.2 closure)"
license='LGPL-2.1-or-later'
origin=paramiko
repo=saphira
url=https://pypi.org/project/paramiko/
source=https://files.pythonhosted.org/packages/1f/e7/81fdcbc7f190cdb058cffc9431587eb289833bdd633e2002455ca9bb13d4/paramiko-4.0.0.tar.gz
sha256=6a25f07b380cc9c9a88d2b920ad37167ac4667f8d9886ccebd8f90f654b5d69f

depends="
    python3
    python-bcrypt
    python-cryptography
    python-invoke
    python-pynacl"

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
