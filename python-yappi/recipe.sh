#!/bin/sh

# python-yappi: yappi: yet another Python profiler (C extension, oslo.service)
#
# yappi 1.7.6, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-yappi
pkgver=1.7.6
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="yappi: yet another Python profiler (C extension, oslo.service)"
license="MIT"
origin=yappi
repo=saphira
url=https://pypi.org/project/yappi/
source=https://files.pythonhosted.org/packages/9f/47/f7ec7744dff1104560d6276f951a8182f5b805e8d86ece591aebd0512845/yappi-1.7.6.tar.gz
sha256=c94281936af77c00c6ac2306a0e7f85a67e354d717120df85fcc5dfb9243d4dd

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
    so=$(ls "$PKGDEST"/usr/lib/python3.14/site-packages/_yappi*.so \
        2>/dev/null | head -1)
    [ -n "$so" ] || {
        echo "ERROR: python-yappi staged payload is missing the compiled extension (_yappi)" >&2
        return 1
    }
}
