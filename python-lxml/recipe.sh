#!/bin/sh

# python-lxml: lxml XML/HTML toolkit (nova/cinder dependency)
#
# lxml 6.1.1, vendored sdist, links the native libxml2/libxslt.
# Compiled C extension (setuptools); asserted staged below.

pkgname=python-lxml
pkgver=6.1.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="lxml XML/HTML toolkit (OpenStack 2026.2 closure)"
license='BSD-3-Clause'
origin=lxml
repo=saphira
url=https://pypi.org/project/lxml/
source=https://files.pythonhosted.org/packages/05/3b/aab6728cae887456f409b4d75e8a01856e4f04bd510de38052a47768b680/lxml-6.1.1.tar.gz
sha256=ba96ae44888e0185281e937633a743ea90d5a196c6000f82565ebb0580012d40

depends="
    python3
    libxml2
    libxslt
"

makedepends="
    python3
    python3-pip
    python3-dev
    setuptools
    wheel
    gcc
    pkgconf
    libxml2-dev
    libxslt-dev
    zlib-dev
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
    # the compiled extension must actually be staged (lxml has no
    # pure-python fallback; a missing .so would fail silently late)
    staged=$(find "$PKGDEST" -name 'etree.*.so' | head -1)
    [ -n "$staged" ] || {
        echo "ERROR: staged payload is missing the compiled lxml extensions" >&2
        return 1
    }
}
