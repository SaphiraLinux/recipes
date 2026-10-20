#!/bin/sh

# python-xstatic-objectpath: objectpath 1.2.1 (XStatic packaging standard)
#
# XStatic-objectpath 1.2.1.1, vendored sdist, installed offline into system
# site-packages. Frontend asset bundle for Horizon; pure data.

pkgname=python-xstatic-objectpath
pkgver=1.2.1.1
pkgrel=1
pkgarch=noarch
pkgdesc="objectpath 1.2.1 (XStatic packaging standard) (OpenStack 2026.2 closure)"
license='MIT'
origin=XStatic-objectpath
repo=saphira
url=https://pypi.org/project/XStatic-objectpath/
source=https://files.pythonhosted.org/packages/90/c1/80f3398f7ed16b39c06aeccea6e259610f0b2562c65a4451855221c2c27e/xstatic_objectpath-1.2.1.1.tar.gz
sha256=5980ef04519a9d30078ec46c693c7f3a10c93e21b98663cb1e6e9461497d5048

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
