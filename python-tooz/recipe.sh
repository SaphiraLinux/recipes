#!/bin/sh

# python-tooz: Coordination library for distributed systems.
#
# tooz 9.1.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-tooz
pkgver=9.1.0
pkgrel=1
pkgarch=noarch
pkgdesc="Coordination library for distributed systems. (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=tooz
repo=saphira
url=https://pypi.org/project/tooz/
source=https://files.pythonhosted.org/packages/a2/2e/934cfa2c24b1c55e8a1c5a56bd7570bdae007d2c8548b9edd991711438e2/tooz-9.1.0.tar.gz
sha256=69d1fea697abeb6a739219b7eaa348552aae0b0aac3d9550cbd625cbaf0e3e0a

depends="
    python3
    python-fasteners
    python-futurist
    python-msgpack
    python-oslo-serialization
    python-oslo-utils
    python-stevedore
    python-tenacity
    python-voluptuous"

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
