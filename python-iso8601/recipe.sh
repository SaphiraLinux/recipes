#!/bin/sh

# python-iso8601: iso8601: simple ISO 8601 date/time parser
#
# iso8601 2.1.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-iso8601
pkgver=2.1.0
pkgrel=1
pkgarch=noarch
pkgdesc="iso8601: simple ISO 8601 date/time parser"
license="MIT"
origin=iso8601
repo=saphira
url=https://pypi.org/project/iso8601/
source=https://files.pythonhosted.org/packages/b9/f3/ef59cee614d5e0accf6fd0cbba025b93b272e626ca89fb70a3e9187c5d15/iso8601-2.1.0.tar.gz
sha256=6b1d3829ee8921c4301998c909f7829fa9ed3cbdac0d3b16af2d743aed1ba8df

depends="
    python3
"
makedepends="
    python3
    python3-pip
    python-poetry-core
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
