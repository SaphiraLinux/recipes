#!/bin/sh

# python-cachetools: cachetools: extensible memoizing collections and decorators
#
# cachetools 7.1.8, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.
#
# 7.1.8 (not the OpenStack 2026.2 upper-constraint 7.1.7): this is the
# version saphira-unified-memory-mcp de-vendors to, so the standalone
# package must satisfy it. cachetools is an unconstrained transitive dep
# for OpenStack; the minor bump is API-compatible.

pkgname=python-cachetools
pkgver=7.1.8
pkgrel=1
pkgarch=noarch
pkgdesc="cachetools: extensible memoizing collections and decorators"
license="MIT"
origin=cachetools
repo=saphira
url=https://pypi.org/project/cachetools/
source=https://files.pythonhosted.org/packages/4b/39/9a4689914dd907915cee74733b95888fc1d8a21aad47a24a0a2deec73ac4/cachetools-7.1.8.tar.gz
sha256=1221d547a0b24b7f26fa891d40d488b5258beab9aebd8ed68c729be3af849c43

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
