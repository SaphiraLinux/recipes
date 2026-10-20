#!/bin/sh

# python-oslo-context: oslo.context: OpenStack request context
#
# oslo.context 6.5.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-oslo-context
pkgver=6.5.0
pkgrel=1
pkgarch=noarch
pkgdesc="oslo.context: OpenStack request context"
license="Apache-2.0"
origin=oslo.context
repo=saphira
url=https://pypi.org/project/oslo.context/
source=https://files.pythonhosted.org/packages/5b/6b/71f00290f6fb7302178422d3478093aacf972ab3e6e0f4b9a91026f533f8/oslo_context-6.5.0.tar.gz
sha256=7e1fb03c6a97167959f37d930300154e0ee837ecdb85798c2bbe8878b56caaaf

depends="
    python3
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
