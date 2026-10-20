#!/bin/sh

# python-pyperclip: A cross-platform clipboard module for Python. (Only handles plain text for now.)
#
# pyperclip 1.11.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-pyperclip
pkgver=1.11.0
pkgrel=1
pkgarch=noarch
pkgdesc="A cross-platform clipboard module for Python. (Only handles plain text for now.) (OpenStack 2026.2 closure)"
license='BSD-3-Clause'
origin=pyperclip
repo=saphira
url=https://pypi.org/project/pyperclip/
source=https://files.pythonhosted.org/packages/e8/52/d87eba7cb129b81563019d1679026e7a112ef76855d6159d24754dbd2a51/pyperclip-1.11.0.tar.gz
sha256=244035963e4428530d9e3a6101a1ef97209c6825edab1567beac148ccc1db1b6

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
