#!/bin/sh

# python-msgpack: msgpack: MessagePack serializer (C extension preserved)
#
# msgpack 1.2.1, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-msgpack
pkgver=1.2.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="msgpack: MessagePack serializer (C extension preserved)"
license="Apache-2.0"
origin=msgpack
repo=saphira
url=https://pypi.org/project/msgpack/
source=https://files.pythonhosted.org/packages/31/f9/c0a1c127f9049db9155afc316952ea571720dd01833ff5e4d7e8e6352dbb/msgpack-1.2.1.tar.gz
sha256=04c721c2c7448767e9e3f2520a475663d8ee0f09c31890f6d2bd70fd636a9647

depends="
    python3
"
makedepends="
    python3
    python3-pip
    setuptools
    wheel
    gcc
    python3-dev
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
    so=$(ls "$PKGDEST"/usr/lib/python3.14/site-packages/msgpack/_cmsgpack*.so \
        2>/dev/null | head -1)
    [ -n "$so" ] || {
        echo "ERROR: python-msgpack staged payload is missing the compiled extension (msgpack._cmsgpack)" >&2
        return 1
    }
}
