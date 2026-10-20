#!/bin/sh

# python-wsme: Simplify the writing of REST APIs, and extend them with additional protocols.
#
# WSME 0.13.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-wsme
pkgver=0.13.0
pkgrel=1
pkgarch=noarch
pkgdesc="Simplify the writing of REST APIs, and extend them with additional protocols. (OpenStack 2026.2 closure)"
license='MIT'
origin=WSME
repo=saphira
url=https://pypi.org/project/WSME/
source=https://files.pythonhosted.org/packages/2b/78/b78fda48cc560127744fb7349945a7af5f4de94a77d2b08f204aa22389b2/wsme-0.13.0.tar.gz
sha256=5bf32010ed943ecfb3f08795a4602e2683df5d5ea8cc71eaf1ebe3f449f39833

depends="
    python3
    python-importlib-metadata
    python-netaddr
    python-simplegeneric
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
