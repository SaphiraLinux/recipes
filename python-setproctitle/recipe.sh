#!/bin/sh

# python-setproctitle: process title setter (neutron-lib dependency)
#
# setproctitle 1.3.7, vendored sdist. Tiny compiled C extension
# (setuptools); asserted staged below.

pkgname=python-setproctitle
pkgver=1.3.7
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="process title setter (OpenStack 2026.2 closure)"
license='BSD-3-Clause'
origin=setproctitle
repo=saphira
url=https://pypi.org/project/setproctitle/
source=https://files.pythonhosted.org/packages/8d/48/49393a96a2eef1ab418b17475fb92b8fcfad83d099e678751b05472e69de/setproctitle-1.3.7.tar.gz
sha256=bc2bc917691c1537d5b9bca1468437176809c7e11e5694ca79a9ca12345dcb9e

depends="
    python3
"

makedepends="
    python3
    python3-pip
    python3-dev
    setuptools
    wheel
    gcc
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
    # compiled extension must actually be staged (no silent fallback).
    # The module is setproctitle._setproctitle, so the object is
    # setproctitle/_setproctitle.<tag>.so, not setproctitle.<tag>.so.
    staged=$(find "$PKGDEST" -name '_setproctitle.*.so' | head -1)
    [ -n "$staged" ] || {
        echo "ERROR: staged payload is missing the compiled setproctitle extension" >&2
        return 1
    }
}
