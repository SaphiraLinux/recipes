#!/bin/sh

# python-pynacl: NaCl networking and cryptography library (paramiko dependency)
#
# PyNaCl 1.6.2, vendored sdist, links the native libsodium.
# Compiled extension (setuptools); asserted staged below.

pkgname=python-pynacl
pkgver=1.6.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="NaCl networking and cryptography library (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=pynacl
repo=saphira
url=https://pypi.org/project/PyNaCl/
source=https://files.pythonhosted.org/packages/d9/9a/4019b524b03a13438637b11538c82781a5eda427394380381af8f04f467a/pynacl-1.6.2.tar.gz
sha256=018494d6d696ae03c7e656e5e74cdfd8ea1326962cc401bcf018f1ed8436811c

depends="
    python3
    python-cffi
    libsodium
"

makedepends="
    python3
    python3-pip
    python3-dev
    setuptools
    python-setuptools-scm
    wheel
    gcc
    make
    pkgconf
    python-cffi
    libsodium
    libsodium-dev
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
    staged=$(find "$PKGDEST" -name '_sodium.*.so' -o -name 'nacl._sodium.*.so' | head -1)
    [ -n "$staged" ] || {
        echo "ERROR: staged payload is missing the compiled pynacl extension" >&2
        return 1
    }
}
