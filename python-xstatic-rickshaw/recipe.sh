#!/bin/sh

# python-xstatic-rickshaw: Rickshaw 1.5.1 (XStatic packaging standard)
#
# XStatic-Rickshaw 1.5.1.3, vendored sdist, installed offline into system
# site-packages. Frontend asset bundle for Horizon; pure data.

pkgname=python-xstatic-rickshaw
pkgver=1.5.1.3
pkgrel=1
pkgarch=noarch
pkgdesc="Rickshaw 1.5.1 (XStatic packaging standard) (OpenStack 2026.2 closure)"
license='MIT'
origin=XStatic-Rickshaw
repo=saphira
url=https://pypi.org/project/XStatic-Rickshaw/
source=https://files.pythonhosted.org/packages/25/77/087dcea5c09ac5509ab45846873925a691a415076d8f7702c4d697e31d57/xstatic_rickshaw-1.5.1.3.tar.gz
sha256=d5b72ff0a374b5d5b50952098e8bf8f402516d2e641ee5034f087a3faa1e4082

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
