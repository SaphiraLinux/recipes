#!/bin/sh

# python-invoke: Pythonic task execution
#
# invoke 3.0.3, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-invoke
pkgver=3.0.3
pkgrel=1
pkgarch=noarch
pkgdesc="Pythonic task execution (OpenStack 2026.2 closure)"
license='BSD-3-Clause'
origin=invoke
repo=saphira
url=https://pypi.org/project/invoke/
source=https://files.pythonhosted.org/packages/33/f6/227c48c5fe47fa178ccf1fda8f047d16c97ba926567b661e9ce2045c600c/invoke-3.0.3.tar.gz
sha256=437b6a622223824380bfb4e64f612711a6b648c795f565efc8625af66fb57f0c

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
