#!/bin/sh

# python-oslo-upgradecheck: oslo.upgradecheck: upgrade-check framework for OpenStack services
#
# oslo.upgradecheck 2.8.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-oslo-upgradecheck
pkgver=2.8.0
pkgrel=1
pkgarch=noarch
pkgdesc="oslo.upgradecheck: upgrade-check framework for OpenStack services"
license="Apache-2.0"
origin=oslo.upgradecheck
repo=saphira
url=https://pypi.org/project/oslo.upgradecheck/
source=https://files.pythonhosted.org/packages/61/a3/3a5fe5f6e870de5c1a350ec019369b1ee50a99b45973ed318207e4139e8c/oslo_upgradecheck-2.8.0.tar.gz
sha256=7656ecc54a08191f86d9a21eb9bdf43fb7dc305b9cef4c9aa577a027f2ee3740

depends="
    python3
    python-oslo-config
    python-oslo-i18n
    python-prettytable
    python-oslo-utils
    python-oslo-policy
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
