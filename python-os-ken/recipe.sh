#!/bin/sh

# python-os-ken: A component-based software defined networking framework for OpenStack
#
# os-ken 4.2.2, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-os-ken
pkgver=4.2.2
pkgrel=1
pkgarch=noarch
pkgdesc="A component-based software defined networking framework for OpenStack (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=os-ken
repo=saphira
url=https://pypi.org/project/os-ken/
source=https://files.pythonhosted.org/packages/c0/81/3dc912cca417f80d5b0871904c6e1b7b7002de867b5a7981f2a8d1d45c43/os_ken-4.2.2.tar.gz
sha256=bf6a640c0e67c377d4e6c0014f1de36bbf53d16eb7ecb080e5f9b5ede9bbf836

depends="
    python3
    packaging
    python-eventlet
    python-msgpack
    python-ncclient
    python-netaddr
    python-oslo-config
    python-ovs
    python-pbr
    python-routes
    python-webob"

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
