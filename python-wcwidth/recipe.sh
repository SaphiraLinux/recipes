#!/bin/sh

# python-wcwidth: wcwidth: terminal column width (prettytable dependency)
#
# wcwidth 0.9.2, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.
#
# The optional C extension (wcwidth._wcwidth_c, built from the vendored
# libwcwidth/ sources, stable ABI abi3) is REQUIRED here, not optional:
# upstream's setup.py falls back to a pure-Python wheel when the compiler
# is missing, which is how the same python-wcwidth-0.9.2-r1 identity was
# published both with and without the compiled object. CIBUILDWHEEL=1 is
# upstream's own "release build" switch that makes the extension
# mandatory, and recipe_install asserts the staged .so exists. The package
# is therefore arch-specific, always carries the compiled extension, and
# preserves the offline build, the musl shared-library link and upstream
# functionality (the C and Python paths are behaviourally equivalent; the
# C path is the performance path upstream ships in wheels).

pkgname=python-wcwidth
pkgver=0.9.2
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="wcwidth: terminal column width (compiled C extension, abi3)"
license="MIT"
origin=wcwidth
repo=saphira
url=https://pypi.org/project/wcwidth/
source=https://files.pythonhosted.org/packages/f0/b4/7830542634bb2d3e62aa3b586a72d5b3b6c91c3168929e7000ef3fed041d/wcwidth-0.9.2.tar.gz
sha256=ae0ef90b90f6af38b54f1fe6d58662ec33b3cb4b8391958a62416d654231727b

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
    # CIBUILDWHEEL=1: upstream's release-build switch. A missing or failed
    # compiler is a hard error instead of a silent pure-Python fallback.
    CIBUILDWHEEL=1 \
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

    # The compiled extension MUST be in the payload: an arch-specific
    # package without it is exactly the defect this revision fixes.
    so=$(ls "$PKGDEST"/usr/lib/python3.14/site-packages/wcwidth/_wcwidth_c*.so \
        2>/dev/null | head -1)
    [ -n "$so" ] || {
        echo "ERROR: python-wcwidth staged payload is missing the compiled" \
             "extension wcwidth/_wcwidth_c*.so (CIBUILDWHEEL=1 should have" \
             "made it mandatory)" >&2
        return 1
    }
}
