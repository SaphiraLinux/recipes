#!/bin/sh

# python-osprofiler: osprofiler: cross-service profiling (Keystone)
#
# osprofiler 4.4.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-osprofiler
pkgver=4.4.0
pkgrel=1
pkgarch=noarch
pkgdesc="osprofiler: cross-service profiling (Keystone)"
license="Apache-2.0"
origin=osprofiler
repo=saphira
url=https://pypi.org/project/osprofiler/
source=https://files.pythonhosted.org/packages/ff/71/9bd056d116d97edbf137afa4b4575bf4e069ec6be8abf69328ac296b1322/osprofiler-4.4.0.tar.gz
sha256=6e08df7eef6afc0d2d027813d40e43cb228f0eb3eb3441d61495c2800ebfa320

depends="
    python3
    python-netaddr
    python-oslo-concurrency
    python-oslo-config
    python-oslo-serialization
    python-oslo-utils
    python-prettytable
    python-requests
    python-webob
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
