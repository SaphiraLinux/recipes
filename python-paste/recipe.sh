#!/bin/sh

# python-paste: Paste 3.10.1
#
# PyPI Paste 3.10.1, vendored sdist, pip-installed offline
# (--no-deps --no-build-isolation, build backends from the repo).
# Native Saphira recipe; no unpinned network installs at build time.

pkgname=python-paste
pkgver=3.10.1
pkgrel=1
pkgarch=noarch
pkgdesc="Paste Python library"
license="MIT"
origin=Paste
repo=saphira
url=https://pypi.org/project/Paste/
source=https://files.pythonhosted.org/packages/d7/1c/6bc9040bf9b4cfc9334f66d2738f952384c106c48882adf6097fed3da966/paste-3.10.1.tar.gz
sha256=1c3d12065a5e8a7a18c0c7be1653a97cf38cc3e9a5a0c8334a9dd992d3a05e4a

depends="
    python3
    setuptools
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
