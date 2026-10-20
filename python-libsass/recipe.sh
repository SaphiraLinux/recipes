#!/bin/sh

# python-libsass: libsass bindings (django-compressor dependency)
#
# libsass 0.23.0, vendored sdist, bundles the libsass C++ sources.
# Compiled extension (setuptools + C++); asserted staged below.

pkgname=python-libsass
pkgver=0.23.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="libsass bindings (OpenStack 2026.2 closure)"
license='MIT'
origin=libsass
repo=saphira
url=https://pypi.org/project/libsass/
source=https://files.pythonhosted.org/packages/79/b4/ab091585eaa77299558e3289ca206846aefc123fb320b5656ab2542c20ad/libsass-0.23.0.tar.gz
sha256=6f209955ede26684e76912caf329f4ccb57e4a043fd77fe0e7348dd9574f1880

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
    # compiled extension must actually be staged (no silent fallback)
    staged=$(find "$PKGDEST" -name '_sass.*.so' | head -1)
    [ -n "$staged" ] || {
        echo "ERROR: staged payload is missing the compiled libsass extension" >&2
        return 1
    }
}
