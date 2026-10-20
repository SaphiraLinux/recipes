#!/bin/sh

# python-testscenarios: testscenarios: scenario-based testing (oslo.db runtime dep)
#
# testscenarios 0.7.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.
# Upstream lists testtools only as a test extra, but testscenarios imports it at module level; it is declared here so the module imports.

pkgname=python-testscenarios
pkgver=0.7.0
pkgrel=1
pkgarch=noarch
pkgdesc="testscenarios: scenario-based testing (oslo.db runtime dep)"
license="Apache-2.0"
origin=testscenarios
repo=saphira
url=https://pypi.org/project/testscenarios/
source=https://files.pythonhosted.org/packages/9c/2c/f2fcea6eddfc860a7836bb9d7376e59ccc8817361a05cdf671c99e49c0f7/testscenarios-0.7.0.tar.gz
sha256=da185ee316d877021beb6395f2d80ced22a99c2876c42d54994e3bad3c3daf4d

depends="
    python3
    python-pbr
    python-testtools
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
