#!/bin/sh

# python-vine: vine: promises/async primitives (amqp/kombu dependency)
#
# vine 5.1.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-vine
pkgver=5.1.0
pkgrel=1
pkgarch=noarch
pkgdesc="vine: promises/async primitives (amqp/kombu dependency)"
license="BSD-3-Clause"
origin=vine
repo=saphira
url=https://pypi.org/project/vine/
source=https://files.pythonhosted.org/packages/bd/e4/d07b5f29d283596b9727dd5275ccbceb63c44a1a82aa9e4bfd20426762ac/vine-5.1.0.tar.gz
sha256=8b62e981d35c41049211cf62a0a1242d8c1ee9bd15bb196ce38aefd6799e61e0

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
