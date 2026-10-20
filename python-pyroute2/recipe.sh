#!/bin/sh

# python-pyroute2: Python Netlink library
#
# pyroute2 0.8.1, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-pyroute2
pkgver=0.8.1
pkgrel=1
pkgarch=noarch
pkgdesc="Python Netlink library (OpenStack 2026.2 closure)"
license='Apache-2.0 OR GPL-2.0-or-later'
origin=pyroute2
repo=saphira
url=https://pypi.org/project/pyroute2/
source=https://files.pythonhosted.org/packages/4d/04/c9060b6cb024d05467e17ea93d3ca4bd2f3b05deb2372b7f79321640e8ad/pyroute2-0.8.1.tar.gz
sha256=b91f4a1f7abb9824637b1fe67e6e4a0a071d98d4a1a1b47ef792304ff3adad11

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
