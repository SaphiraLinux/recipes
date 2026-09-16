#!/bin/sh

# Cython 3.3.0: Python-to-C compiler.
#
# Build tooling, not runtime: the aio-libs in-tree backends
# (frozenlist, yarl, propcache) cythonize their .pyx at wheel
# build time when Cython is importable, and crash without it
# (NameError, not the graceful pure fallback). Self-hosting
# sdist (pre-generated C included), legacy setup.py backend.

pkgname=cython
pkgver=3.3.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Python-to-C compiler for extension modules"
license="Apache-2.0"
origin=cython
repo=saphira
url=https://cython.org/
source=https://files.pythonhosted.org/packages/a9/d8/4981ef716ad0e3ff0d3ef383aefc6b03c4a88dee33b272bf8e0d833001ca/cython-3.3.0.tar.gz
sha256=eed0d93fbca7087f143b42c34b05a825849bdf17f101572c2105acfa49aa88b8

depends="
    python3
"
makedepends="
    python3
    python3-dev
    python3-pip
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
        --no-deps \
        --no-build-isolation \
        --no-compile \
        --root "$PKGDEST" \
        --prefix /usr \
        "$SRC"
    test -x "$PKGDEST/usr/bin/cython" ||
        { echo "ERROR: cython CLI missing from payload" >&2; return 1; }
}
