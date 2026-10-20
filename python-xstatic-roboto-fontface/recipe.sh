#!/bin/sh

# python-xstatic-roboto-fontface: roboto-fontface 0.8.0 (XStatic packaging standard)
#
# XStatic-roboto-fontface 0.8.0.1, vendored sdist, installed offline into system
# site-packages. Frontend asset bundle for Horizon; pure data.

pkgname=python-xstatic-roboto-fontface
pkgver=0.8.0.1
pkgrel=1
pkgarch=noarch
pkgdesc="roboto-fontface 0.8.0 (XStatic packaging standard) (OpenStack 2026.2 closure)"
license='MIT'
origin=XStatic-roboto-fontface
repo=saphira
url=https://pypi.org/project/XStatic-roboto-fontface/
source=https://files.pythonhosted.org/packages/0c/99/5bca85d99826a72ed4fce7f914f3c7b5c9ad598460b0fadf1d8732b421e7/xstatic_roboto_fontface-0.8.0.1.tar.gz
sha256=811c90838ccbc0530fc1a574ec0eae3fe79cbfd4c1b10a8c6ea2922cab7c73b2

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
