#!/bin/sh

# python-testtools: testtools: extensions to the Python unittest framework
#
# testtools 2.9.1, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-testtools
pkgver=2.9.1
pkgrel=1
pkgarch=noarch
pkgdesc="testtools: extensions to the Python unittest framework"
license="MIT"
origin=testtools
repo=saphira
url=https://pypi.org/project/testtools/
source=https://files.pythonhosted.org/packages/8b/80/af955640b4e8348aaa8026f9f48304811ec3342d9928ddb611d38a190ea0/testtools-2.9.1.tar.gz
sha256=39ad9eb9e1b935d6838f4b3aee4d6e72db65df5602f6feda998dbb4fe8de0b19

depends="
    python3
    python-fixtures
    python-pbr
"
makedepends="
    python3
    python3-pip
    python-hatchling
    setuptools
    python-hatch-vcs
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
