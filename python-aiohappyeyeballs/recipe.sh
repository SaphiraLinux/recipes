#!/bin/sh

# Happy Eyeballs connection racing: Happy Eyeballs connection racing for asyncio
#
# PyPI aiohappyeyeballs 2.7.1, vendored sdist, pip-installed offline
# (--no-deps --no-build-isolation, build backends from the repo).
# poetry-core backend (published); pure Python.

pkgname=python-aiohappyeyeballs
pkgver=2.7.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Happy Eyeballs connection racing for asyncio"
license="PSF-2.0"
origin=aiohappyeyeballs
repo=saphira
url=https://pypi.org/project/aiohappyeyeballs/
source=https://files.pythonhosted.org/packages/ce/f4/eec0465c2f67b2664688d0240b3212d5196fd89e741df67ddb81f8d35658/aiohappyeyeballs-2.7.1.tar.gz
sha256=065665c041c42a5938ed220bdcd7230f22527fbec085e1853d2402c8a3615d9d

depends="
    python3
"
makedepends="
    python3
    python3-pip
    setuptools
    wheel
    python-poetry-core
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
