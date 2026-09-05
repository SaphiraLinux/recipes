#!/bin/sh

pkgname=python-charset-normalizer
pkgver=3.4.9
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Python charset detection library"
license="MIT"
origin=charset-normalizer
repo=saphira
url=https://pypi.org/project/charset-normalizer/
source=https://files.pythonhosted.org/packages/bd/2a/23f34ec9d04624958e137efdc394888716353190e75f25dd22c7a2c7a8aa/charset_normalizer-3.4.9.tar.gz
sha256=673611bbd43f0810bec0b0f028ddeaaa501190339cac411f347ac76917c3ae7b

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
