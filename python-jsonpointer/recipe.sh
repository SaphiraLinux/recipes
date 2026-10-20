#!/bin/sh

# python-jsonpointer: Identify specific nodes in a JSON document (RFC 6901)
#
# jsonpointer 3.1.1, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-jsonpointer
pkgver=3.1.1
pkgrel=1
pkgarch=noarch
pkgdesc="Identify specific nodes in a JSON document (RFC 6901) (OpenStack 2026.2 closure)"
license='BSD-3-Clause'
origin=jsonpointer
repo=saphira
url=https://pypi.org/project/jsonpointer/
source=https://files.pythonhosted.org/packages/18/c7/af399a2e7a67fd18d63c40c5e62d3af4e67b836a2107468b6a5ea24c4304/jsonpointer-3.1.1.tar.gz
sha256=0b801c7db33a904024f6004d526dcc53bbb8a4a0f4e32bfd10beadf60adf1900

depends="
    python3
"

makedepends="
    python3
    python3-pip
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
