#!/bin/sh

# python-websockify: Websockify.
#
# websockify 0.13.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-websockify
pkgver=0.13.0
pkgrel=1
pkgarch=noarch
pkgdesc="Websockify. (OpenStack 2026.2 closure)"
license='LGPL-3.0-only'
origin=websockify
repo=saphira
url=https://pypi.org/project/websockify/
source=https://files.pythonhosted.org/packages/f7/9e/fa7b6322fe22a02cf34256cbe300a9468533038b1262c7960119a787b595/websockify-0.13.0.tar.gz
sha256=9969731116653226c4c499a8a50712c8f3f7c105c615ead7ebc6ae781f0ba954

depends="
    python3
    python-jwcrypto
    python-numpy
    python-redis
    python-requests"

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
