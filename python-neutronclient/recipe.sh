#!/bin/sh

# python-neutronclient: CLI and Client Library for OpenStack Networking
#
# python-neutronclient 14.0.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-neutronclient
pkgver=14.0.0
pkgrel=1
pkgarch=noarch
pkgdesc="CLI and Client Library for OpenStack Networking (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=python-neutronclient
repo=saphira
url=https://pypi.org/project/python-neutronclient/
source=https://files.pythonhosted.org/packages/b4/5b/1af04d85cf6c3340686d058eb5580e2bbc3249084cdbe60391bbfa57a2a6/python_neutronclient-14.0.0.tar.gz
sha256=9f7ba93e6845e381b833eb54c8fd143160b8fa026c383078f9ac39de7f3c5d19

depends="
    python3
    python-cliff
    python-debtcollector
    python-keystoneauth1
    python-keystoneclient
    python-netaddr
    python-openstacksdk
    python-osc-lib
    python-oslo-i18n
    python-oslo-log
    python-oslo-serialization
    python-oslo-utils
    python-pbr
    python-requests"

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
