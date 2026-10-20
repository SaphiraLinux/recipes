#!/bin/sh

# python-futurist: futurist: useful additions to concurrent.futures
#
# futurist 3.5.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-futurist
pkgver=3.5.0
pkgrel=1
pkgarch=noarch
pkgdesc="futurist: useful additions to concurrent.futures"
license="Apache-2.0"
origin=futurist
repo=saphira
url=https://pypi.org/project/futurist/
source=https://files.pythonhosted.org/packages/f1/82/eb917bf6aa03197ac5bb3ce8a95bee2243a938426ec60747a52cbed9344e/futurist-3.5.0.tar.gz
sha256=97d01f6144bbe3abe1b2155cb2b42dab4ec33e09f4f7f7df7569f35d9a29aaf7

depends="
    python3
    python-debtcollector
"
makedepends="
    python3
    python3-pip
    python-pbr
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
