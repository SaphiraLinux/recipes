#!/bin/sh

pkgname=setuptools
pkgver=84.2.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Python package build system"
license="MIT"
origin=setuptools
repo=saphira
url=https://pypi.org/project/setuptools/
source=https://files.pythonhosted.org/packages/70/b3/c19426f783614d625699a4b247faf628ea9ab1db228674491767b417f9e1/setuptools-84.2.1.tar.gz
sha256=3ff8b3b5492a0aa66960f4419365a86b84e013070d4313e4d4a6894f5d64d6bc

depends="
    python3
"

makedepends="
    python3
    python3-pip
"

recipe_build()
{
    :
}

recipe_install()
{
    PYTHONPATH="$SRC:/usr/lib/python3.14/site-packages" \
        python3 -m pip install \
        --no-deps \
        --no-build-isolation \
        --no-compile \
        --root "$PKGDEST" \
        --prefix /usr \
        "$SRC"
}
