#!/bin/sh

# python-warlock: Python object model built on JSON schema and JSON patch.
#
# warlock 2.1.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-warlock
pkgver=2.1.0
pkgrel=1
pkgarch=noarch
pkgdesc="Python object model built on JSON schema and JSON patch. (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=warlock
repo=saphira
url=https://pypi.org/project/warlock/
source=https://files.pythonhosted.org/packages/29/c2/3ba4daeddd47f1cfdbc703048cbee27bcbc50535261a2bbe36412565f3c9/warlock-2.1.0.tar.gz
sha256=82319ba017341e7fcdc81efc2be9dd2f8237a0da07c71476b5425651b317b1c9

depends="
    python3
    python-jsonpatch
    python-jsonschema"

makedepends="
    python3
    python3-pip
    python-flit-core
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
