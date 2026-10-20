#!/bin/sh

# python-oslo-privsep: oslo.privsep: privileged operation separation for OpenStack
#
# oslo.privsep 3.12.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-oslo-privsep
pkgver=3.12.0
pkgrel=1
pkgarch=noarch
pkgdesc="oslo.privsep: privileged operation separation for OpenStack"
license="Apache-2.0"
origin=oslo.privsep
repo=saphira
url=https://pypi.org/project/oslo.privsep/
source=https://files.pythonhosted.org/packages/61/ba/745a51d54e6c716dfecf97e179885aa3ed52a1f97d7b51f34920d0e672b4/oslo_privsep-3.12.0.tar.gz
sha256=166edcd4a3e982f4ea851308df6408bc6ad5323fbdd83ad6b2a79faed50b9617

depends="
    python3
    python-oslo-log
    python-oslo-i18n
    python-oslo-config
    python-oslo-utils
    python-cffi
    python-msgpack
    python-debtcollector
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
