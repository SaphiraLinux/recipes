#!/bin/sh

# python-xstatic-angular: Angular 1.8.2 (XStatic packaging standard)
#
# XStatic-Angular 1.8.2.3, vendored sdist, installed offline into system
# site-packages. Frontend asset bundle for Horizon; pure data.

pkgname=python-xstatic-angular
pkgver=1.8.2.3
pkgrel=1
pkgarch=noarch
pkgdesc="Angular 1.8.2 (XStatic packaging standard) (OpenStack 2026.2 closure)"
license='MIT'
origin=XStatic-Angular
repo=saphira
url=https://pypi.org/project/XStatic-Angular/
source=https://files.pythonhosted.org/packages/37/b5/ed80c1189f0e0cdc16613b3acd4f3d4f14dd774ca36e43d548513e3b6d8f/xstatic_angular-1.8.2.3.tar.gz
sha256=4ad638c12955e8146f5526fe19e08ef33fb63f901b503ec59ccb030bf268337e

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
