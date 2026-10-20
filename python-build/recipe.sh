#!/bin/sh

# python-build: PEP 517 package builder (cmd2 build requirement)
#
# build 1.6.1, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-build
pkgver=1.6.1
pkgrel=1
pkgarch=noarch
pkgdesc="PEP 517 package builder (OpenStack 2026.2 closure)"
license='MIT'
origin=build
repo=saphira
url=https://pypi.org/project/build/
source=https://files.pythonhosted.org/packages/bd/67/4898a44ea4f3f8e213b0954ec0aa0a16971d62a6212d6ea3931e97115b99/build-1.6.1.tar.gz
sha256=51cc11666391ab6f092070437ac747002ff46f3e4113a3622177ee6b488bfc53

depends="
    python3
    packaging
    python-pyproject-hooks
    python-colorama
"

makedepends="
    python3
    python3-pip
    python-flit-core
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
