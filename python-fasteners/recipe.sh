#!/bin/sh

# python-fasteners: fasteners: cross-platform file/process locks (oslo.concurrency)
#
# fasteners 0.20, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-fasteners
pkgver=0.20
pkgrel=1
pkgarch=noarch
pkgdesc="fasteners: cross-platform file/process locks (oslo.concurrency)"
license="Apache-2.0"
origin=fasteners
repo=saphira
url=https://pypi.org/project/fasteners/
source=https://files.pythonhosted.org/packages/2d/18/7881a99ba5244bfc82f06017316ffe93217dbbbcfa52b887caa1d4f2a6d3/fasteners-0.20.tar.gz
sha256=55dce8792a41b56f727ba6e123fcaee77fd87e638a6863cec00007bfea84c8d8

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
