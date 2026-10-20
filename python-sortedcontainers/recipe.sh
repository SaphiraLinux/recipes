#!/bin/sh

# python-sortedcontainers: Sorted Containers -- Sorted List, Sorted Dict, Sorted Set
#
# sortedcontainers 2.4.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-sortedcontainers
pkgver=2.4.0
pkgrel=1
pkgarch=noarch
pkgdesc="Sorted Containers -- Sorted List, Sorted Dict, Sorted Set (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=sortedcontainers
repo=saphira
url=https://pypi.org/project/sortedcontainers/
source=https://files.pythonhosted.org/packages/e8/c4/ba2f8066cceb6f23394729afe52f3bf7adec04bf9ed2c820b39e19299111/sortedcontainers-2.4.0.tar.gz
sha256=25caa5a06cc30b6b83d11423433f65d1f9d76c4c6a0c90e3379eaa43b9bfdb88

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
