#!/bin/sh

# python-xstatic-tv4: tv4 1.2.7 (XStatic packaging standard)
#
# XStatic-tv4 1.2.7.1, vendored sdist, installed offline into system
# site-packages. Frontend asset bundle for Horizon; pure data.

pkgname=python-xstatic-tv4
pkgver=1.2.7.1
pkgrel=1
pkgarch=noarch
pkgdesc="tv4 1.2.7 (XStatic packaging standard) (OpenStack 2026.2 closure)"
license='MIT'
origin=XStatic-tv4
repo=saphira
url=https://pypi.org/project/XStatic-tv4/
source=https://files.pythonhosted.org/packages/a4/1d/237680657bced9f37d689eb10e1907de95f18d15374255dd14e054614652/xstatic_tv4-1.2.7.1.tar.gz
sha256=83a5b8c6684bde446c76901c7f8e267e35728f3e6497263a5171bea841a06747

depends="
    python3
    python-xstatic
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
