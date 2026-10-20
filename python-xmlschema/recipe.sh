#!/bin/sh

# python-xmlschema: xmlschema: XML Schema validation (pysaml2)
#
# xmlschema 2.5.1, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-xmlschema
pkgver=2.5.1
pkgrel=1
pkgarch=noarch
pkgdesc="xmlschema: XML Schema validation (pysaml2)"
license="MIT"
origin=xmlschema
repo=saphira
url=https://pypi.org/project/xmlschema/
source=https://files.pythonhosted.org/packages/59/af/42e9e773eaa6bc8e8c322f93c75454b0d370979048b250bfef7786ff26ec/xmlschema-2.5.1.tar.gz
sha256=4f7497de6c8b6dc2c28ad7b9ed6e21d186f4afe248a5bea4f54eedab4da44083

depends="
    python3
    python-elementpath
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
