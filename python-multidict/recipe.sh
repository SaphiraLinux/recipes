#!/bin/sh

# Multidict implementation: Multidict implementation for aiohttp
#
# PyPI multidict 6.8.0, vendored sdist, pip-installed offline
# (--no-deps --no-build-isolation, build backends from the repo).
# setuptools backend; C extension compiled with gcc.

pkgname=python-multidict
pkgver=6.8.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Multidict implementation for aiohttp"
license="Apache-2.0"
origin=multidict
repo=saphira
url=https://pypi.org/project/multidict/
source=https://files.pythonhosted.org/packages/14/95/989c1b5ca17b72128661530cd6e351a0a83cda9a4d6c036e9ed976c18931/multidict-6.8.0.tar.gz
sha256=5cd4637ce76312ba1e05eb9c5193fec231f64fee0944e135fa1e951242355b37

depends="
    python3
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
