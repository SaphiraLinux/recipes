#!/bin/sh

pkgname=python-pycparser
pkgver=3.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Python C parser in pure Python"
license="BSD-3-Clause"
origin=pycparser
repo=saphira
url=https://pypi.org/project/pycparser/
source=https://files.pythonhosted.org/packages/1b/7d/92392ff7815c21062bea51aa7b87d45576f649f16458d78b7cf94b9ab2e6/pycparser-3.0.tar.gz
sha256=600f49d217304a5902ac3c37e1281c9fe94e4d0489de643a9504c5cdfdfc6b29

depends="
    python3
"

makedepends="
    python3
    python3-pip
    setuptools
    wheel
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
