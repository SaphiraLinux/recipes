#!/bin/sh

# python-oslo-versionedobjects: Oslo Versioned Objects library
#
# oslo.versionedobjects 3.12.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-oslo-versionedobjects
pkgver=3.12.0
pkgrel=1
pkgarch=noarch
pkgdesc="Oslo Versioned Objects library (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=oslo.versionedobjects
repo=saphira
url=https://pypi.org/project/oslo.versionedobjects/
source=https://files.pythonhosted.org/packages/ab/de/2881d6845b0a72f54e5a30d90dbe0404193819249eb73179f6d5053673c7/oslo_versionedobjects-3.12.0.tar.gz
sha256=7bf14e5845d2f27670ef3b6d9c8757b00363f7f9f1404d23ee969ade70f6ab99

depends="
    python3
    python-netaddr
    python-oslo-config
    python-oslo-context
    python-oslo-i18n
    python-oslo-log
    python-oslo-messaging
    python-oslo-utils"

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
