#!/bin/sh

# python-xstatic-hogan: Hogan 2.0.0 (XStatic packaging standard)
#
# XStatic-Hogan 2.0.0.5, vendored sdist, installed offline into system
# site-packages. Frontend asset bundle for Horizon; pure data.

pkgname=python-xstatic-hogan
pkgver=2.0.0.5
pkgrel=1
pkgarch=noarch
pkgdesc="Hogan 2.0.0 (XStatic packaging standard) (OpenStack 2026.2 closure)"
license='MIT'
origin=XStatic-Hogan
repo=saphira
url=https://pypi.org/project/XStatic-Hogan/
source=https://files.pythonhosted.org/packages/f9/16/d5d08fd56c3e3285f701b26329bbf5f819dd7bb532f3e8cde64d6affa010/xstatic_hogan-2.0.0.5.tar.gz
sha256=40c07eb1e78e2aeed06d39e44b2e985eb7c8cec13a07e9c70982c687464489f9

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
