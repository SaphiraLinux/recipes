#!/bin/sh

# python-openstacksdk: An SDK for building applications to work with OpenStack
#
# openstacksdk 4.20.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-openstacksdk
pkgver=4.20.0
pkgrel=1
pkgarch=noarch
pkgdesc="An SDK for building applications to work with OpenStack (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=openstacksdk
repo=saphira
url=https://pypi.org/project/openstacksdk/
source=https://files.pythonhosted.org/packages/38/3b/7d0bb61a25002fb0023e2f0e620cb7e78dcd7b79d555005700fc13d92888/openstacksdk-4.20.0.tar.gz
sha256=f533050d7441b6d41c53488434d2f2df79f1f963a4b431695b4c7f49380ea85c

depends="
    python3
    python-cryptography
    python-decorator
    python-dogpile-cache
    python-iso8601
    python-jmespath
    python-jsonpatch
    python-keystoneauth1
    python-os-service-types
    python-pbr
    python-platformdirs
    python-psutil
    pyyaml"

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
