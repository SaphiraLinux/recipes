#!/bin/sh

# python-ncclient: Python library for NETCONF clients
#
# ncclient 0.7.1, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-ncclient
pkgver=0.7.1
pkgrel=1
pkgarch=noarch
pkgdesc="Python library for NETCONF clients (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=ncclient
repo=saphira
url=https://pypi.org/project/ncclient/
source=https://files.pythonhosted.org/packages/ef/92/e36995ee7ce151814335583571bed95f1a5a491b7ea4d5487cb67377800a/ncclient-0.7.1.tar.gz
sha256=60dabb6ac1a2d84fbc3349cb104ef7d0c5d12cf8eee43fefc715410d70410ddc

depends="
    python3
    python-lxml
    python-paramiko"

makedepends="
    python3
    python3-pip
    python-hatchling
    python-hatch-vcs
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
