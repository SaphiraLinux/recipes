#!/bin/sh

# python-xstatic-bootswatch: bootswatch 3.3.7 (XStatic packaging standard)
#
# XStatic-bootswatch 3.3.7.1, vendored sdist, installed offline into system
# site-packages. Frontend asset bundle for Horizon; pure data.

pkgname=python-xstatic-bootswatch
pkgver=3.3.7.1
pkgrel=1
pkgarch=noarch
pkgdesc="bootswatch 3.3.7 (XStatic packaging standard) (OpenStack 2026.2 closure)"
license='MIT'
origin=XStatic-bootswatch
repo=saphira
url=https://pypi.org/project/XStatic-bootswatch/
source=https://files.pythonhosted.org/packages/a6/d9/ffc8c72378b1d9d1ef784473aa8215721f2f7a5151c8c8f1f126324fc180/xstatic_bootswatch-3.3.7.1.tar.gz
sha256=f77cc3cbbd714dc2e6da4cc54fb03c6070e59a9c2d52c6d352972d45aad7e674

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
