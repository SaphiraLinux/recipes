#!/bin/sh

# python-fixtures: fixtures: reusable state/setup helpers for tests
#
# fixtures 4.3.2, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-fixtures
pkgver=4.3.2
pkgrel=1
pkgarch=noarch
pkgdesc="fixtures: reusable state/setup helpers for tests"
license="Apache-2.0"
origin=fixtures
repo=saphira
url=https://pypi.org/project/fixtures/
source=https://files.pythonhosted.org/packages/79/fc/da17efe78bb35b945441170363328ad11d953d69e6273bceb668b1d68c34/fixtures-4.3.2.tar.gz
sha256=b7db64014732513f23d12b0c49ae527ba0c0c1f2667ec97d9136d67157ebce5d

depends="
    python3
    python-pbr
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
