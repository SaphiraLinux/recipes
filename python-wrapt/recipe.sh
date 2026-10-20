#!/bin/sh

# python-wrapt: wrapt: transparent object proxies (C extension preserved)
#
# wrapt 2.5.1, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-wrapt
pkgver=2.5.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="wrapt: transparent object proxies (C extension preserved)"
license="BSD-2-Clause"
origin=wrapt
repo=saphira
url=https://pypi.org/project/wrapt/
source=https://files.pythonhosted.org/packages/04/22/89e2f3bdae5cb34e0cab0cd86d7172dbf418de4b46c9b17b9c7a560dfa44/wrapt-2.5.1.tar.gz
sha256=f595bb0185aab3e9dc31950c95d914f56ea8278810c3b928f3426e12ed6d27bc

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
    WRAPT_INSTALL_EXTENSIONS=true \
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
    so=$(ls "$PKGDEST"/usr/lib/python3.14/site-packages/wrapt/_wrappers*.so \
        2>/dev/null | head -1)
    [ -n "$so" ] || {
        echo "ERROR: python-wrapt staged payload is missing the compiled extension (wrapt._wrappers)" >&2
        return 1
    }
}
