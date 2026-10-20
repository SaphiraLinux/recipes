#!/bin/sh

# python-os-vif: A library for plugging and unplugging virtual interfaces in OpenStack.
#
# os-vif 5.2.2, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-os-vif
pkgver=5.2.2
pkgrel=1
pkgarch=noarch
pkgdesc="A library for plugging and unplugging virtual interfaces in OpenStack. (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=os-vif
repo=saphira
url=https://pypi.org/project/os-vif/
source=https://files.pythonhosted.org/packages/9e/49/38db4dcb17561a560cd6731ad19b771621a6c7601720c3bb8c6886739188/os_vif-5.2.2.tar.gz
sha256=e88e1d3a3c72a4e34f864b07b05203eb3386e6ef3e5ea9a36c3ce5a11ae762e1

depends="
    python3
    python-debtcollector
    python-oslo-concurrency
    python-oslo-config
    python-oslo-i18n
    python-oslo-log
    python-oslo-privsep
    python-oslo-serialization
    python-oslo-utils
    python-oslo-versionedobjects
    python-ovsdbapp
    python-pbr
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
