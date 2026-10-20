#!/bin/sh

# python-oslo-limit: Limit enforcement library to assist with quota calculation.
#
# oslo.limit 2.12.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-oslo-limit
pkgver=2.12.0
pkgrel=1
pkgarch=noarch
pkgdesc="Limit enforcement library to assist with quota calculation. (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=oslo.limit
repo=saphira
url=https://pypi.org/project/oslo.limit/
source=https://files.pythonhosted.org/packages/c9/2a/760e01cc767941e4b19f140dfc245d5d09cff97c788d918a394468eca478/oslo_limit-2.12.0.tar.gz
sha256=60f792faa04485a265d7dab5d83571ad7d7ceb455f05883d04ae3f048f1298a2

depends="
    python3
    python-keystoneauth1
    python-openstacksdk
    python-oslo-config
    python-oslo-i18n
    python-oslo-log"

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
