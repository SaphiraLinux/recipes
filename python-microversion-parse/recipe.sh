#!/bin/sh

# python-microversion-parse: OpenStack microversion header parser
#
# microversion-parse 2.1.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-microversion-parse
pkgver=2.1.0
pkgrel=1
pkgarch=noarch
pkgdesc="OpenStack microversion header parser (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=microversion-parse
repo=saphira
url=https://pypi.org/project/microversion-parse/
source=https://files.pythonhosted.org/packages/be/63/9892f437c8c2e327cc8c5355c1e9fcef0440482badae0a531d53a4369755/microversion_parse-2.1.0.tar.gz
sha256=57367847ecc6a4328258c88d63681f3cc91b6021d3ec284a351fb78e87d057ea

depends="
    python3
    python-webob"

makedepends="
    python3
    python3-pip
    python-pbr
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
