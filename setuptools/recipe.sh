#!/bin/sh

pkgname=setuptools
pkgver=80.10.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Python package build system"
license="MIT"
origin=setuptools
repo=saphira
url=https://pypi.org/project/setuptools/
source=https://files.pythonhosted.org/packages/76/95/faf61eb8363f26aa7e1d762267a8d602a1b26d4f3a1e758e92cb3cb8b054/setuptools-80.10.2.tar.gz
sha256=8b0e9d10c784bf7d262c4e5ec5d4ec94127ce206e8738f29a437945fbc219b70

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
