#!/bin/sh

# python-async-timeout: Timeout context manager for asyncio programs
#
# async-timeout 5.0.1, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-async-timeout
pkgver=5.0.1
pkgrel=1
pkgarch=noarch
pkgdesc="Timeout context manager for asyncio programs (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=async-timeout
repo=saphira
url=https://pypi.org/project/async-timeout/
source=https://files.pythonhosted.org/packages/a5/ae/136395dfbfe00dfc94da3f3e136d0b13f394cba8f4841120e34226265780/async_timeout-5.0.1.tar.gz
sha256=d9321a7a3d5a6a5e187e824d2fa0793ce379a202935782d555d6e9d2735677d3

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
