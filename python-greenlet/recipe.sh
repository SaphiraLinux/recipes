#!/bin/sh

# python-greenlet: greenlet: lightweight in-process concurrent programming (C extension)
#
# greenlet 3.5.5, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-greenlet
pkgver=3.5.5
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="greenlet: lightweight in-process concurrent programming (C extension)"
license="MIT"
origin=greenlet
repo=saphira
url=https://pypi.org/project/greenlet/
source=https://files.pythonhosted.org/packages/0b/d8/7cc97c142388aef03f622e001c572c4f84e9252a439549d483f555771970/greenlet-3.5.5.tar.gz
sha256=adb4bae02e91a8e863e48b177e4014bdcac8a6b5e047ea1df687a61534b85e6c

depends="
    python3
"
makedepends="
    python3
    python3-pip
    setuptools
    wheel
    gcc
    python3-dev
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
    so=$(ls "$PKGDEST"/usr/lib/python3.14/site-packages/greenlet/_greenlet*.so \
        2>/dev/null | head -1)
    [ -n "$so" ] || {
        echo "ERROR: python-greenlet staged payload is missing the compiled extension (greenlet._greenlet)" >&2
        return 1
    }
}
