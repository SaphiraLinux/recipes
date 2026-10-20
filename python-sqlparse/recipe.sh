#!/bin/sh

# python-sqlparse: A non-validating SQL parser.
#
# sqlparse 0.6.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-sqlparse
pkgver=0.6.0
pkgrel=1
pkgarch=noarch
pkgdesc="A non-validating SQL parser. (OpenStack 2026.2 closure)"
license='BSD-3-Clause'
origin=sqlparse
repo=saphira
url=https://pypi.org/project/sqlparse/
source=https://files.pythonhosted.org/packages/5f/d3/3f06a1006f2261d1342aefb3c71eed02f5d4ca5bdbecd86ebc12ad38306e/sqlparse-0.6.0.tar.gz
sha256=113c35c75365ab9cc9c7231d68c6428fb11c085fc8e9eb1ad659b7ddbf6cd2b9

depends="
    python3
"

makedepends="
    python3
    python3-pip
    python-hatchling
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
