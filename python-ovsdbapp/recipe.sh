#!/bin/sh

# python-ovsdbapp: A library for creating OVSDB applications
#
# ovsdbapp 2.19.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-ovsdbapp
pkgver=2.19.0
pkgrel=1
pkgarch=noarch
pkgdesc="A library for creating OVSDB applications (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=ovsdbapp
repo=saphira
url=https://pypi.org/project/ovsdbapp/
source=https://files.pythonhosted.org/packages/13/03/08abd8115f35b9b3f4ba31e6022f312ee1e5c594adf3bebc194931aa8b62/ovsdbapp-2.19.0.tar.gz
sha256=554d091d52553a801756f178d91d108f29fe9936d13955de853c4cdc142d196d

depends="
    python3
    python-fixtures
    python-netaddr
    python-ovs
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
