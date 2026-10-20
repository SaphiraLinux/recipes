#!/bin/sh

# python-defusedxml: defusedxml: XML bomb protection (pysaml2)
#
# defusedxml 0.7.1, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-defusedxml
pkgver=0.7.1
pkgrel=1
pkgarch=noarch
pkgdesc="defusedxml: XML bomb protection (pysaml2)"
license="PSF-2.0"
origin=defusedxml
repo=saphira
url=https://pypi.org/project/defusedxml/
source=https://files.pythonhosted.org/packages/0f/d5/c66da9b79e5bdb124974bfe172b4daf3c984ebd9c2a06e2b8a4dc7331c72/defusedxml-0.7.1.tar.gz
sha256=1bb3032db185915b62d7c6209c5a8792be6a32ab2fedacc84e01b52c51aa3e69

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
