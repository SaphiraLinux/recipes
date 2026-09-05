#!/bin/sh

pkgname=python-configargparse
pkgver=1.7.5
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Python argparse with config file and env variable support"
license="MIT"
origin=configargparse
repo=saphira
url=https://pypi.org/project/ConfigArgParse/
source=https://files.pythonhosted.org/packages/3f/0b/30328302903c55218ffc5199646d0e9d28348ff26c02ba77b2ffc58d294a/configargparse-1.7.5.tar.gz
sha256=e3f9a7bb6be34d66b2e3c4a2f58e3045f8dfae47b0dc039f87bcfaa0f193fb0f

depends="
    python3
"

makedepends="
    python3
    python3-pip
    setuptools
    wheel
    python-vcs-versioning
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
