#!/bin/sh

# python-oauthlib: oauthlib: OAuth request-signing logic (Keystone)
#
# oauthlib 3.3.1, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-oauthlib
pkgver=3.3.1
pkgrel=1
pkgarch=noarch
pkgdesc="oauthlib: OAuth request-signing logic (Keystone)"
license="BSD-3-Clause"
origin=oauthlib
repo=saphira
url=https://pypi.org/project/oauthlib/
source=https://files.pythonhosted.org/packages/0b/5f/19930f824ffeb0ad4372da4812c50edbd1434f678c90c2733e1188edfc63/oauthlib-3.3.1.tar.gz
sha256=0f0f8aa759826a193cf66c12ea1af1637f87b9b4622d46e866952bb022e538c9

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
