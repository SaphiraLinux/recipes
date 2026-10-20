#!/bin/sh

# python-prompt-toolkit: Library for building powerful interactive command lines in Python
#
# prompt-toolkit 3.0.53, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-prompt-toolkit
pkgver=3.0.53
pkgrel=1
pkgarch=noarch
pkgdesc="Library for building powerful interactive command lines in Python (OpenStack 2026.2 closure)"
license='BSD-3-Clause'
origin=prompt-toolkit
repo=saphira
url=https://pypi.org/project/prompt-toolkit/
source=https://files.pythonhosted.org/packages/7d/ea/39b988c938f75cb75d7045b5c69f8bfed47ee2152c8837fb403de29d6fb8/prompt_toolkit-3.0.53.tar.gz
sha256=9ec8a0ad96d5c56148b3f914aa79c1564c3fde5d2e6b876e7bc327e353cf8fa6

depends="
    python3
    python-wcwidth"

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
