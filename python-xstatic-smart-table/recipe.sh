#!/bin/sh

# python-xstatic-smart-table: smart-table 1.4.13 (XStatic packaging standard)
#
# XStatic-smart-table 1.4.13.3, vendored sdist, installed offline into system
# site-packages. Frontend asset bundle for Horizon; pure data.

pkgname=python-xstatic-smart-table
pkgver=1.4.13.3
pkgrel=1
pkgarch=noarch
pkgdesc="smart-table 1.4.13 (XStatic packaging standard) (OpenStack 2026.2 closure)"
license='MIT'
origin=XStatic-smart-table
repo=saphira
url=https://pypi.org/project/XStatic-smart-table/
source=https://files.pythonhosted.org/packages/af/c3/ed1851399a5975447e5758bc3b3198f882709d0888a36512c6c706d98740/xstatic_smart_table-1.4.13.3.tar.gz
sha256=a1e9e058ecee10f62db3a55b97cf79f350a845c9f5e0863e15e04a5c19349112

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
