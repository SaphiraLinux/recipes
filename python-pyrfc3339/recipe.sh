#!/bin/sh

pkgname=python-pyrfc3339
pkgver=2.1.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Python RFC3339 timestamp generation and parsing"
license="MIT"
origin=pyrfc3339
repo=saphira
url=https://pypi.org/project/pyRFC3339/
source=https://files.pythonhosted.org/packages/b4/7f/3c194647ecb80ada6937c38a162ab3edba85a8b6a58fa2919405f4de2509/pyrfc3339-2.1.0.tar.gz
sha256=c569a9714faf115cdb20b51e830e798c1f4de8dabb07f6ff25d221b5d09d8d7f

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
