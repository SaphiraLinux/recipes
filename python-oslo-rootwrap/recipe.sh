#!/bin/sh

# python-oslo-rootwrap: Oslo Rootwrap
#
# oslo.rootwrap 7.10.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-oslo-rootwrap
pkgver=7.10.0
pkgrel=1
pkgarch=noarch
pkgdesc="Oslo Rootwrap (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=oslo.rootwrap
repo=saphira
url=https://pypi.org/project/oslo.rootwrap/
source=https://files.pythonhosted.org/packages/7d/c7/f9aea00df0b93d36948d7e8b82e7e7de626e03ee80115cedf523d54c96c7/oslo_rootwrap-7.10.0.tar.gz
sha256=99c24f763c3f1f0be96652e416a099b486115d9709dcfa73310f48168cf89a44

depends="
    python3
    python-debtcollector
    python-pbr"

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
