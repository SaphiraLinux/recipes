#!/bin/sh

# python-autopage: A library to provide automatic paging for console output
#
# autopage 0.6.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-autopage
pkgver=0.6.0
pkgrel=1
pkgarch=noarch
pkgdesc="A library to provide automatic paging for console output (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=autopage
repo=saphira
url=https://pypi.org/project/autopage/
source=https://files.pythonhosted.org/packages/75/76/9078d8db91f29af9ac5a359757f63f2d0fa869aba704d5ef0f836db62ea1/autopage-0.6.0.tar.gz
sha256=42d07de90de63e83762828028bfd56d19906a18f7c951ef6eef3e9ad48a3071d

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
