#!/bin/sh

# asyncio callback registry: asyncio callback registry for aiohttp
#
# PyPI aiosignal 1.4.0, vendored sdist, pip-installed offline
# (--no-deps --no-build-isolation, build backends from the repo).
# Runtime edge to frozenlist only; setuptools backend.

pkgname=python-aiosignal
pkgver=1.4.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="asyncio callback registry for aiohttp"
license="Apache-2.0"
origin=aiosignal
repo=saphira
url=https://pypi.org/project/aiosignal/
source=https://files.pythonhosted.org/packages/61/62/06741b579156360248d1ec624842ad0edf697050bbaf7c3e46394e106ad1/aiosignal-1.4.0.tar.gz
sha256=f47eecd9468083c2029cc99945502cb7708b082c232f9aca65da147157b251c7

depends="
    python3
    python-frozenlist
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
        --no-deps \
        --no-build-isolation \
        --no-compile \
        --root "$PKGDEST" \
        --prefix /usr \
        "$SRC"
}
