#!/bin/sh

# python-repoze-lru: repoze.lru: LRU cache implementation (Routes dependency)
#
# repoze.lru 0.8, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-repoze-lru
pkgver=0.8
pkgrel=1
pkgarch=noarch
pkgdesc="repoze.lru: LRU cache implementation (Routes dependency)"
license="BSD-2-Clause"
origin=repoze.lru
repo=saphira
url=https://pypi.org/project/repoze.lru/
source=https://files.pythonhosted.org/packages/b5/19/727d5c904ea513a6a9044bf43beaa2c5e632e017b1e0ab71e9d111d20967/repoze_lru-0.8.tar.gz
sha256=a252408cd93fe670c88d6665b96fe5d42e071dba2507a1f21a1e609ae4fa891a

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
