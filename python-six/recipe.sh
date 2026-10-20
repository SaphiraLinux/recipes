#!/bin/sh

# python-six: six 1.17.0
#
# PyPI six 1.17.0, vendored sdist, pip-installed offline
# (--no-deps --no-build-isolation, build backends from the repo).
# Native Saphira recipe; no unpinned network installs at build time.

pkgname=python-six
pkgver=1.17.0
pkgrel=1
pkgarch=noarch
pkgdesc="six Python library"
license="MIT"
origin=six
repo=saphira
url=https://pypi.org/project/six/
source=https://files.pythonhosted.org/packages/94/e7/b2c673351809dca68a0e064b6af791aa332cf192da575fd474ed7d6f16a2/six-1.17.0.tar.gz
sha256=ff70335d468e7eb6ec65b95b99d3a2836546063f63acc5171de367e834932a81

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
