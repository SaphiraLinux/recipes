#!/bin/sh

# python-rcssmin: CSS Minifier
#
# rcssmin 1.2.2, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-rcssmin
pkgver=1.2.2
pkgrel=1
pkgarch=noarch
pkgdesc="CSS Minifier (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=rcssmin
repo=saphira
url=https://pypi.org/project/rcssmin/
source=https://files.pythonhosted.org/packages/81/af/c9654b4f9b054ec163ed7cb20d8db0e5ae05e2e9ce99a4c11d91a2180b3f/rcssmin-1.2.2.tar.gz
sha256=806986eaf7414545edc28a1d29523e9560e49e151ff4a337d9d1f0271d6e1cc4

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
