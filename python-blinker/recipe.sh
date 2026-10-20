#!/bin/sh

# python-blinker: blinker: fast in-process signals (Flask dependency)
#
# blinker 1.9.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-blinker
pkgver=1.9.0
pkgrel=1
pkgarch=noarch
pkgdesc="blinker: fast in-process signals (Flask dependency)"
license="MIT"
origin=blinker
repo=saphira
url=https://pypi.org/project/blinker/
source=https://files.pythonhosted.org/packages/21/28/9b3f50ce0e048515135495f198351908d99540d69bfdc8c1d15b73dc55ce/blinker-1.9.0.tar.gz
sha256=b4ce2265a7abece45e7cc896e98dbebe6cead56bcf805a3d23136d145f5445bf

depends="
    python3
"
makedepends="
    python3
    python3-pip
    python-flit-core
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
