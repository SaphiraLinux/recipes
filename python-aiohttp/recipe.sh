#!/bin/sh

# Async HTTP client and server framework: Async HTTP client and server framework
#
# PyPI aiohttp 3.14.3, vendored sdist, pip-installed offline
# (--no-deps --no-build-isolation, build backends from the repo).
# setuptools backend; C speedups (http parser, websocket) compiled with gcc. New-style deps only (propcache/yarl/aiohappyeyeballs); async-timeout is py<3.11-only and stays out on 3.14.

pkgname=python-aiohttp
pkgver=3.14.3
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Async HTTP client and server framework"
license="Apache-2.0"
origin=aiohttp
repo=saphira
url=https://pypi.org/project/aiohttp/
source=https://files.pythonhosted.org/packages/58/d9/22ce5786ac0c1653ae8b6c23bded02c1686d11f0dbb45b31ce128e0df985/aiohttp-3.14.3.tar.gz
sha256=9491196535a88924a60afd5b5f434b5b203b6cc616250878dbdb223a8f7844bc

depends="
    python3
    python-aiohappyeyeballs
    python-aiosignal
    python-attrs
    python-frozenlist
    python-multidict
    python-propcache
    python-yarl
"
makedepends="
    python3
    python3-pip
    setuptools
    wheel
    python3-dev
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
