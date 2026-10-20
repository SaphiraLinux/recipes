#!/bin/sh

# python-numpy: NumPy numerical computing (websockify/horizon dependency)
#
# numpy 2.4.6, vendored sdist, meson-python backend. Compiled
# extensions; asserted staged below. No BLAS/LAPACK in the universe:
# builds against the reference routines (documented, not silent).

pkgname=python-numpy
pkgver=2.4.6
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="NumPy numerical computing (OpenStack 2026.2 closure)"
license='BSD-3-Clause'
origin=numpy
repo=saphira
url=https://pypi.org/project/numpy/
source=https://files.pythonhosted.org/packages/d0/ad/fed0499ce6a338d2a03ebae59cd15093910c8875328855781952abf6c2fe/numpy-2.4.6.tar.gz
sha256=f3a3570c4a2a16746ac2c31a7c7c7b0c186b95ce902e33db6f28094ed7387dda

depends="
    python3
"

makedepends="
    python3
    python3-pip
    python3-dev
    gcc
    pkgconf
    ninja
    meson
    cython
    python-meson-python
    python-pyproject-metadata
    packaging
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
    staged=$(find "$PKGDEST" -name '_multiarray_umath.*.so' | head -1)
    [ -n "$staged" ] || {
        echo "ERROR: staged payload is missing the compiled numpy extensions" >&2
        return 1
    }
}
