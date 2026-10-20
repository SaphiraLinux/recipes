#!/bin/sh

# python-testresources: testresources: unit test resource management (oslo.db runtime dep)
#
# testresources 2.1.2, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-testresources
pkgver=2.1.2
pkgrel=1
pkgarch=noarch
pkgdesc="testresources: unit test resource management (oslo.db runtime dep)"
license="Apache-2.0"
origin=testresources
repo=saphira
url=https://pypi.org/project/testresources/
source=https://files.pythonhosted.org/packages/5f/f4/5e0ecad96a86bc58f7833fc26ae623a67c49148f56327b11dfddf30aa176/testresources-2.1.2.tar.gz
sha256=a2b1266fd6cb89295dbb79e3442e5ff1c27db35a0b62b84c7846002676d12ae2

depends="
    python3
    python-pbr
"
makedepends="
    python3
    python3-pip
    python-hatchling
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
