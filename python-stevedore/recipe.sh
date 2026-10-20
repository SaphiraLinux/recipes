#!/bin/sh

# python-stevedore: stevedore: manage dynamic plugins for Python applications
#
# stevedore 5.9.1, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-stevedore
pkgver=5.9.1
pkgrel=1
pkgarch=noarch
pkgdesc="stevedore: manage dynamic plugins for Python applications"
license="Apache-2.0"
origin=stevedore
repo=saphira
url=https://pypi.org/project/stevedore/
source=https://files.pythonhosted.org/packages/db/a1/3b8ed9c1fc3aa6eebb57732d924ddaa0500ecc3b638d0454816320994383/stevedore-5.9.1.tar.gz
sha256=e97a2667923efda926e8713fde6a73616df68210a3cbc6f02b48967b676fd8bf

depends="
    python3
    python-pbr
"
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
