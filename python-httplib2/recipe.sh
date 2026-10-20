#!/bin/sh

# python-httplib2: A comprehensive HTTP client library.
#
# httplib2 0.32.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-httplib2
pkgver=0.32.0
pkgrel=2
pkgarch=noarch
pkgdesc="A comprehensive HTTP client library. (OpenStack 2026.2 closure)"
license='MIT'
origin=httplib2
repo=saphira
url=https://pypi.org/project/httplib2/
source=https://files.pythonhosted.org/packages/84/f5/ccf58de92d61e3ad921119668f54ed36ca1d0cf5dcc5c1657dfb164fd78b/httplib2-0.32.0.tar.gz
sha256=48a0ef30a42db65d8f3399045e1d09ab0ba66e3b9efc360d07f80ea55d286025

depends="
    python3
    pyparsing"

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
