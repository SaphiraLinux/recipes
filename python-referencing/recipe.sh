#!/bin/sh

# python-referencing: referencing: JSON reference resolution (jsonschema)
#
# referencing 0.37.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-referencing
pkgver=0.37.0
pkgrel=1
pkgarch=noarch
pkgdesc="referencing: JSON reference resolution (jsonschema)"
license="MIT"
origin=referencing
repo=saphira
url=https://pypi.org/project/referencing/
source=https://files.pythonhosted.org/packages/22/f5/df4e9027acead3ecc63e50fe1e36aca1523e1719559c499951bb4b53188f/referencing-0.37.0.tar.gz
sha256=44aefc3142c5b842538163acb373e24cce6632bd54bdb01b21ad5863489f50d8

depends="
    python3
    python-attrs
    python-rpds-py
    typing-extensions
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
