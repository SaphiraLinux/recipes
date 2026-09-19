#!/bin/sh

# Fast property caching: Fast property caching for aiohttp and yarl
#
# PyPI propcache 0.5.2, vendored sdist, pip-installed offline
# (--no-deps --no-build-isolation, build backends from the repo).
# In-tree pep517 backend; C extension compiled with gcc.

pkgname=python-propcache
pkgver=0.5.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Fast property caching for aiohttp and yarl"
license="Apache-2.0"
origin=propcache
repo=saphira
url=https://pypi.org/project/propcache/
source=https://files.pythonhosted.org/packages/ec/44/c87281c333769159c50594f22610f77398a47ccbfbbf23074e744e86f87c/propcache-0.5.2.tar.gz
sha256=01c4fc7480cd0598bb4b57022df55b9ca296da7fc5a8760bd8451a7e63a7d427

depends="
    python3
"
makedepends="
    python3
    python3-pip
    setuptools
    wheel
    python3-dev
    python-expandvars
    cython
    gcc
"

recipe_build()
{
    :
}

recipe_install()
{
    python3 -m pip install \
        --no-deps \
        --no-build-isolation \
        --no-compile \
        --root "$PKGDEST" \
        --prefix /usr \
        "$SRC"
}
