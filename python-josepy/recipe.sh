#!/bin/sh

pkgname=python-josepy
pkgver=2.2.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Python JOSE (JSON Object Signing and Encryption) implementation"
license="Apache-2.0"
origin=josepy
repo=saphira
url=https://pypi.org/project/josepy/
source=https://files.pythonhosted.org/packages/7f/ad/6f520aee9cc9618d33430380741e9ef859b2c560b1e7915e755c084f6bc0/josepy-2.2.0.tar.gz
sha256=74c033151337c854f83efe5305a291686cef723b4b970c43cfe7270cf4a677a9

# Requires cryptography>=1.5 at runtime (not yet ported).
depends="
    python3
    python-cryptography
"

makedepends="
    python3
    python3-pip
    setuptools
    wheel
    python-poetry-core
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
}
