#!/bin/sh

# Microsoft Edge neural text-to-speech client: Microsoft Edge neural text-to-speech client
#
# PyPI edge-tts 7.2.8, vendored sdist, pip-installed offline
# (--no-deps --no-build-isolation, build backends from the repo).
# LGPLv3 overall (one MIT file); needs network at RUNTIME (cloud voices) - packaging carries no credentials. Legacy setup.py backend.

pkgname=python-edge-tts
pkgver=7.2.8
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Microsoft Edge neural text-to-speech client"
license="LGPL-3.0-only AND MIT"
origin=edge-tts
repo=saphira
url=https://pypi.org/project/edge-tts/
source=https://files.pythonhosted.org/packages/3f/60/afbf548b43c78355e03926c6b1fff7500303a2da4d84db9e1324119e21ae/edge_tts-7.2.8.tar.gz
sha256=fcf185a0d527a0d2d003f9d5841facc1d5e0e7b3b88d5df9c32990402c6b8cd0

depends="
    python3
    python-aiohttp
    certifi
    python-tabulate
    typing-extensions
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
