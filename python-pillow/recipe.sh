#!/bin/sh

# python-pillow: Python Imaging Library (horizon dependency)
#
# Pillow 12.3.0, vendored sdist. Compiled extensions against native
# libjpeg-turbo, zlib, libpng and freetype; asserted staged below.

pkgname=python-pillow
pkgver=12.3.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Python Imaging Library (OpenStack 2026.2 closure)"
license='HPND'
origin=Pillow
repo=saphira
url=https://pypi.org/project/Pillow/
source=https://files.pythonhosted.org/packages/1c/3d/bb7fca845737cf9d7dbde16ed1843984665ff2e0a518f5db43e77ec540b9/pillow-12.3.0.tar.gz
sha256=3b8182a766685eaa002637e28b4ec8d6b18819a0c71f579bf0dbaa5830297cce

depends="
    python3
    libjpeg-turbo
    zlib
    libpng
    freetype
"

makedepends="
    python3
    python3-pip
    python3-dev
    setuptools
    wheel
    python-pybind11
    gcc
    pkgconf
    libjpeg-turbo-dev
    zlib-dev
    libpng
    freetype
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
    # compiled extensions must actually be staged (no silent fallback)
    staged=$(find "$PKGDEST" -name '_imaging.*.so' | head -1)
    [ -n "$staged" ] || {
        echo "ERROR: staged payload is missing the compiled Pillow extensions" >&2
        return 1
    }
}
