#!/bin/sh

pkgname=python-cffi
pkgver=2.0.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Python foreign function interface (C ABI)"
license="MIT"
origin=cffi
repo=saphira
url=https://pypi.org/project/cffi/
source=https://files.pythonhosted.org/packages/eb/56/b1ba7935a17738ae8453301356628e8147c79dbb825bcbc73dc7401f9846/cffi-2.0.0.tar.gz
sha256=44d1b5909021139fe36001ae048dbdde8214afa20200eda0f64c068cac5d5529

depends="
    python3
    python-pycparser
"

makedepends="
    python3
    python3-dev
    python3-pip
    setuptools
    wheel
    gcc
    libffi-dev
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
