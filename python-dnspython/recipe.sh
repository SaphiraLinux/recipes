#!/bin/sh

# python-dnspython: dnspython: DNS toolkit (eventlet dependency)
#
# dnspython 2.8.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.
# 2.9.0 moved to the uv_build backend, which would require the uv toolchain to build offline; 2.8.0 is the newest release buildable from source with the repo's hatchling.

pkgname=python-dnspython
pkgver=2.8.0
pkgrel=1
pkgarch=noarch
pkgdesc="dnspython: DNS toolkit (eventlet dependency)"
license="ISC"
origin=dnspython
repo=saphira
url=https://pypi.org/project/dnspython/
source=https://files.pythonhosted.org/packages/8c/8b/57666417c0f90f08bcafa776861060426765fdb422eb10212086fb811d26/dnspython-2.8.0.tar.gz
sha256=181d3c6996452cb1189c4046c61599b84a5a86e099562ffde77d26984ff26d0f

depends="
    python3
    python-cryptography
"
makedepends="
    python3
    python3-pip
    python-hatchling
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
