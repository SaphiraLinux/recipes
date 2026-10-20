#!/bin/sh

# python-psutil: psutil: process and system utilities (C extension preserved)
#
# psutil 7.2.2, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-psutil
pkgver=7.2.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="psutil: process and system utilities (C extension preserved)"
license="BSD-3-Clause"
origin=psutil
repo=saphira
url=https://pypi.org/project/psutil/
source=https://files.pythonhosted.org/packages/aa/c6/d1ddf4abb55e93cebc4f2ed8b5d6dbad109ecb8d63748dd2b20ab5e57ebe/psutil-7.2.2.tar.gz
sha256=0746f5f8d406af344fd547f1c8daa5f5c33dbc293bb8d6a16d80b4bb88f59372

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
    so=$(ls "$PKGDEST"/usr/lib/python3.14/site-packages/psutil/_psutil*.so \
        2>/dev/null | head -1)
    [ -n "$so" ] || {
        echo "ERROR: python-psutil staged payload is missing the compiled extension (psutil._psutil_*)" >&2
        return 1
    }
}
