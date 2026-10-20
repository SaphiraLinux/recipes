#!/bin/sh

# python-jsonschema-specifications: jsonschema-specifications: JSON Schema dialect metaschemas
#
# jsonschema-specifications 2025.9.1, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-jsonschema-specifications
pkgver=2025.9.1
pkgrel=1
pkgarch=noarch
pkgdesc="jsonschema-specifications: JSON Schema dialect metaschemas"
license="MIT"
origin=jsonschema-specifications
repo=saphira
url=https://pypi.org/project/jsonschema-specifications/
source=https://files.pythonhosted.org/packages/19/74/a633ee74eb36c44aa6d1095e7cc5569bebf04342ee146178e2d36600708b/jsonschema_specifications-2025.9.1.tar.gz
sha256=b540987f239e745613c7a9176f3edb72b832a4ac465cf02712288397832b5e8d

depends="
    python3
    python-referencing
"
makedepends="
    python3
    python3-pip
    python-hatchling
    setuptools
    python-hatch-vcs
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
