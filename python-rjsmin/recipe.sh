#!/bin/sh

# python-rjsmin: Javascript Minifier
#
# rjsmin 1.2.5, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-rjsmin
pkgver=1.2.5
pkgrel=1
pkgarch=noarch
pkgdesc="Javascript Minifier (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=rjsmin
repo=saphira
url=https://pypi.org/project/rjsmin/
source=https://files.pythonhosted.org/packages/59/16/14288d309d0f42c6586440c47bf6ec1a880218f698f30293fa3782db4008/rjsmin-1.2.5.tar.gz
sha256=a3f8040b0273dec773e0e807e86a4d0a9535516c0a0a35aa1bb6de6e15bb1f09

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
