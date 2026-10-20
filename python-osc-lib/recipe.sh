#!/bin/sh

# python-osc-lib: OpenStackClient Library
#
# osc-lib 4.7.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-osc-lib
pkgver=4.7.0
pkgrel=1
pkgarch=noarch
pkgdesc="OpenStackClient Library (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=osc-lib
repo=saphira
url=https://pypi.org/project/osc-lib/
source=https://files.pythonhosted.org/packages/eb/80/37ac2a46cc3ea9348ea670fd76dad72888726191f5875278a3d85034a9d8/osc_lib-4.7.0.tar.gz
sha256=5b896de12ed69fb1111d2971467d403b838d414fc27df2024fc50e8652a53f2b

depends="
    python3
    python-cliff
    python-keystoneauth1
    python-openstacksdk
    python-oslo-i18n
    python-oslo-utils
    python-pbr
    python-requests
    python-stevedore"

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
