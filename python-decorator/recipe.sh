#!/bin/sh

# python-decorator: decorator: decorator for Python functions (dogpile.cache dependency)
#
# decorator 5.3.1, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-decorator
pkgver=5.3.1
pkgrel=1
pkgarch=noarch
pkgdesc="decorator: decorator for Python functions (dogpile.cache dependency)"
license="BSD-2-Clause"
origin=decorator
repo=saphira
url=https://pypi.org/project/decorator/
source=https://files.pythonhosted.org/packages/60/8b/32f9823da46cde7df2087faa08cd98d01b908f8dcab982cdba9c84e85355/decorator-5.3.1.tar.gz
sha256=4cbcdd55a6efadb9dbea26b858f4fb3264567b52d69ca0d25b721b553f60ea82

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
