#!/bin/sh

# python-elementpath: elementpath: XPath 2.0/3.0 selectors (xmlschema)
#
# elementpath 4.8.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-elementpath
pkgver=4.8.0
pkgrel=1
pkgarch=noarch
pkgdesc="elementpath: XPath 2.0/3.0 selectors (xmlschema)"
license="MIT"
origin=elementpath
repo=saphira
url=https://pypi.org/project/elementpath/
source=https://files.pythonhosted.org/packages/ac/41/afdd82534c80e9675d1c51dc21d0889b72d023bfe395a2f5a44d751d3a73/elementpath-4.8.0.tar.gz
sha256=5822a2560d99e2633d95f78694c7ff9646adaa187db520da200a8e9479dc46ae

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
