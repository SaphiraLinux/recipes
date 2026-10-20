#!/bin/sh

# python-keystoneauth1: keystoneauth1: authentication plugins and session for OpenStack clients
#
# keystoneauth1 5.17.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-keystoneauth1
pkgver=5.17.0
pkgrel=1
pkgarch=noarch
pkgdesc="keystoneauth1: authentication plugins and session for OpenStack clients"
license="Apache-2.0"
origin=keystoneauth1
repo=saphira
url=https://pypi.org/project/keystoneauth1/
source=https://files.pythonhosted.org/packages/68/84/a76c0819add727693d89b152c11452650036fcd481274756a33172e386e7/keystoneauth1-5.17.0.tar.gz
sha256=82359acc20c754fcb22818e090e2fea647e4c5c1137a6addb4984e9fba708ab3

depends="
    python3
    python-iso8601
    python-requests
    python-stevedore
    python-os-service-types
    typing-extensions
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
