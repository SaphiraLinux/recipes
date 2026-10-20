#!/bin/sh

# python-pyudev: A libudev binding
#
# pyudev 0.24.4, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-pyudev
pkgver=0.24.4
pkgrel=1
pkgarch=noarch
pkgdesc="A libudev binding (OpenStack 2026.2 closure)"
license='LGPL-2.1-only'
origin=pyudev
repo=saphira
url=https://pypi.org/project/pyudev/
source=https://files.pythonhosted.org/packages/5e/1d/8bdbf651de1002e8b58fbe817bee22b1e8bfcdd24341d42c3238ce9a75f4/pyudev-0.24.4.tar.gz
sha256=e788bb983700b1a84efc2e88862b0a51af2a995d5b86bc9997546505cf7b36bc

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
