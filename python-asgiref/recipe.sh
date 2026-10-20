#!/bin/sh

# python-asgiref: ASGI specs, helper code, and adapters
#
# asgiref 3.12.1, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-asgiref
pkgver=3.12.1
pkgrel=1
pkgarch=noarch
pkgdesc="ASGI specs, helper code, and adapters (OpenStack 2026.2 closure)"
license='BSD-3-Clause'
origin=asgiref
repo=saphira
url=https://pypi.org/project/asgiref/
source=https://files.pythonhosted.org/packages/e6/26/3b59f2bdae5f640389becb1f673cded775287f5fc4f816309d9ca9a3f93d/asgiref-3.12.1.tar.gz
sha256=59dcb51c272ad209d59bed5708a64a333083e86017d7fcdd67498eeab7784340

depends="
    python3
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
