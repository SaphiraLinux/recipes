#!/bin/sh

# python-jsonschema: jsonschema: JSON Schema validation (Keystone)
#
# jsonschema 4.26.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-jsonschema
pkgver=4.26.0
pkgrel=1
pkgarch=noarch
pkgdesc="jsonschema: JSON Schema validation (Keystone)"
license="MIT"
origin=jsonschema
repo=saphira
url=https://pypi.org/project/jsonschema/
source=https://files.pythonhosted.org/packages/b3/fc/e067678238fa451312d4c62bf6e6cf5ec56375422aee02f9cb5f909b3047/jsonschema-4.26.0.tar.gz
sha256=0c26707e2efad8aa1bfc5b7ce170f3fccc2e4918ff85989ba9ffa9facb2be326

depends="
    python3
    python-attrs
    python-jsonschema-specifications
    python-referencing
    python-rpds-py
"
makedepends="
    python3
    python3-pip
    python-hatchling
    setuptools
    python-hatch-vcs
    python-hatch-fancy-pypi-readme
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
