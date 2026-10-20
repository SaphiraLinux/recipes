#!/bin/sh

# python-xstatic-jquery: jQuery 3.7.1 (XStatic packaging standard)
#
# XStatic-jQuery 3.7.1.1, vendored sdist, installed offline into system
# site-packages. Frontend asset bundle for Horizon; pure data.

pkgname=python-xstatic-jquery
pkgver=3.7.1.1
pkgrel=1
pkgarch=noarch
pkgdesc="jQuery 3.7.1 (XStatic packaging standard) (OpenStack 2026.2 closure)"
license='MIT'
origin=XStatic-jQuery
repo=saphira
url=https://pypi.org/project/XStatic-jQuery/
source=https://files.pythonhosted.org/packages/d0/ac/5ad81abc559e6771a019eba7494b981638b63f645d4fd184adbd85a6ca35/xstatic_jquery-3.7.1.1.tar.gz
sha256=0c2ac780d8388bfd8b94586f6a0f86541e8702b5fc96f1ded997866214809445

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
