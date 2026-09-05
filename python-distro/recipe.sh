#!/bin/sh

pkgname=python-distro
pkgver=1.9.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Python OS/platform information library"
license="Apache-2.0"
origin=distro
repo=saphira
url=https://pypi.org/project/distro/
source=https://files.pythonhosted.org/packages/fc/f8/98eea607f65de6527f8a2e8885fc8015d3e6f5775df186e443e0964a11c3/distro-1.9.0.tar.gz
sha256=2fa77c6fd8940f116ee1d6b94a2f90b13b5ea8d019b98bc8bafdcabcdd9bdbed

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
