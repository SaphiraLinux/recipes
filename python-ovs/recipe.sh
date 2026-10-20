#!/bin/sh

# python-ovs: Open vSwitch library
#
# ovs 3.7.1, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-ovs
pkgver=3.7.1
pkgrel=1
pkgarch=noarch
pkgdesc="Open vSwitch library (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=ovs
repo=saphira
url=https://pypi.org/project/ovs/
source=https://files.pythonhosted.org/packages/bc/4c/47f3d3dbfb0bc79324462df512fc2ce0ce3a2b7fa57656d7147f28ae6ab7/ovs-3.7.1.tar.gz
sha256=dbe6c5f5de18fc926b7258fcaf59fd4003ede90b7c34f2829888ea5e854b44c5

depends="
    python3
    python-sortedcontainers"

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
