#!/bin/sh

# URL parsing and manipulation: URL parsing and manipulation for aiohttp
#
# PyPI yarl 1.24.5, vendored sdist, pip-installed offline
# (--no-deps --no-build-isolation, build backends from the repo).
# In-tree pep517 backend; C quoting extension compiled with gcc.

pkgname=python-yarl
pkgver=1.24.5
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="URL parsing and manipulation for aiohttp"
license="Apache-2.0"
origin=yarl
repo=saphira
url=https://pypi.org/project/yarl/
source=https://files.pythonhosted.org/packages/31/33/ebe9e3d1f86c7a0b51094c0a146392045ca1631d2664889539dec8088a33/yarl-1.24.5.tar.gz
sha256=e81b83143bee16329c23db3c1b2d82b29892fcbcb849186d2f6e98a5abe9a57f

depends="
    python3
    idna
    python-multidict
    python-propcache
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
