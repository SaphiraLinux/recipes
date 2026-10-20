#!/bin/sh

# python-oslo-serialization: oslo.serialization: OpenStack serialization utilities
#
# oslo.serialization 5.11.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-oslo-serialization
pkgver=5.11.0
pkgrel=1
pkgarch=noarch
pkgdesc="oslo.serialization: OpenStack serialization utilities"
license="Apache-2.0"
origin=oslo.serialization
repo=saphira
url=https://pypi.org/project/oslo.serialization/
source=https://files.pythonhosted.org/packages/af/f5/2611fb291898fa5f3b41c68e916cb060305cb718a043fdbff25026491fc4/oslo_serialization-5.11.0.tar.gz
sha256=8326e85a80856c1068007423fcf6fe29dd2fe57a32f5d87fff0120b555b4b67c

depends="
    python3
    python-msgpack
    python-oslo-utils
    python-pbr
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
