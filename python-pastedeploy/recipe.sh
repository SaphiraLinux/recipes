#!/bin/sh

# python-pastedeploy: PasteDeploy: load WSGI applications from config files (oslo.service)
#
# PasteDeploy 3.1.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-pastedeploy
pkgver=3.1.0
pkgrel=1
pkgarch=noarch
pkgdesc="PasteDeploy: load WSGI applications from config files (oslo.service)"
license="MIT"
origin=PasteDeploy
repo=saphira
url=https://pypi.org/project/PasteDeploy/
source=https://files.pythonhosted.org/packages/e3/97/0c4a613ec96a54d21daa7e089178263915554320402e89b4e319436a63cb/PasteDeploy-3.1.0.tar.gz
sha256=9ddbaf152f8095438a9fe81f82c78a6714b92ae8e066bed418b6a7ff6a095a95

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
