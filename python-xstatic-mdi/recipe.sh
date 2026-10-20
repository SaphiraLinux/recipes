#!/bin/sh

# python-xstatic-mdi: mdi 1.6.50 (XStatic packaging standard)
#
# XStatic-mdi 1.6.50.3, vendored sdist, installed offline into system
# site-packages. Frontend asset bundle for Horizon; pure data.

pkgname=python-xstatic-mdi
pkgver=1.6.50.3
pkgrel=1
pkgarch=noarch
pkgdesc="mdi 1.6.50 (XStatic packaging standard) (OpenStack 2026.2 closure)"
license='MIT'
origin=XStatic-mdi
repo=saphira
url=https://pypi.org/project/XStatic-mdi/
source=https://files.pythonhosted.org/packages/ab/f8/80db0da1ca9f1142263214c12777e2a40c3c75db28253f2eff8d645fdb72/xstatic_mdi-1.6.50.3.tar.gz
sha256=db3e5bffd5fcd4358970cd0cf6a7a3e927fae8c195ced1f1360a967fde224be2

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
