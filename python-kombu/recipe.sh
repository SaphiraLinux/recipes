#!/bin/sh

# python-kombu: kombu: messaging library for Python (AMQP transport)
#
# kombu 5.6.2, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-kombu
pkgver=5.6.2
pkgrel=1
pkgarch=noarch
pkgdesc="kombu: messaging library for Python (AMQP transport)"
license="BSD-3-Clause"
origin=kombu
repo=saphira
url=https://pypi.org/project/kombu/
source=https://files.pythonhosted.org/packages/b6/a5/607e533ed6c83ae1a696969b8e1c137dfebd5759a2e9682e26ff1b97740b/kombu-5.6.2.tar.gz
sha256=8060497058066c6f5aed7c26d7cd0d3b574990b09de842a8c5aaed0b92cc5a55

depends="
    python3
    python-amqp
    python-vine
    tzdata
    packaging
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
