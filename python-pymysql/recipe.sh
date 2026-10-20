#!/bin/sh

# python-pymysql: PyMySQL 1.2.3
#
# PyPI PyMySQL 1.2.3, vendored sdist, pip-installed offline
# (--no-deps --no-build-isolation, build backends from the repo).
# Native Saphira recipe; no unpinned network installs at build time.

pkgname=python-pymysql
pkgver=1.2.3
pkgrel=1
pkgarch=noarch
pkgdesc="PyMySQL Python library"
license="MIT"
origin=PyMySQL
repo=saphira
url=https://pypi.org/project/PyMySQL/
source=https://files.pythonhosted.org/packages/b1/d4/c15b459e25a23767d2f4065ef40968920320f04e302889574310c21c96a3/pymysql-1.2.3.tar.gz
sha256=d5b288529782e536ae171866df3ca9dc4f6cbfb3cc2f18e6f837fbb90dbc262b

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
