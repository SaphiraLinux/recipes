#!/bin/sh

# python-xstatic-angular-lrdragndrop: Angular-lrdragndrop 1.0.2 (XStatic packaging standard)
#
# XStatic-Angular-lrdragndrop 1.0.2.7, vendored sdist, installed offline into system
# site-packages. Frontend asset bundle for Horizon; pure data.

pkgname=python-xstatic-angular-lrdragndrop
pkgver=1.0.2.7
pkgrel=1
pkgarch=noarch
pkgdesc="Angular-lrdragndrop 1.0.2 (XStatic packaging standard) (OpenStack 2026.2 closure)"
license='MIT'
origin=XStatic-Angular-lrdragndrop
repo=saphira
url=https://pypi.org/project/XStatic-Angular-lrdragndrop/
source=https://files.pythonhosted.org/packages/32/f7/1b8380d41a48aa9b5f6605f4709fb22692d0b0f10652e6e0d0608667299d/xstatic_angular_lrdragndrop-1.0.2.7.tar.gz
sha256=adb047cff657a31139b75b9c1d8975692ed58d50bfea7b712a9f8a6f46fcf2ce

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
