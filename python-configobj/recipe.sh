#!/bin/sh

pkgname=python-configobj
pkgver=5.0.9
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Python config file reader/writer with validation"
license="BSD-3-Clause"
origin=configobj
repo=saphira
url=https://pypi.org/project/configobj/
source=https://files.pythonhosted.org/packages/f5/c4/c7f9e41bc2e5f8eeae4a08a01c91b2aea3dfab40a3e14b25e87e7db8d501/configobj-5.0.9.tar.gz
sha256=03c881bbf23aa07bccf1b837005975993c4ab4427ba57f959afdd9d1a2386848

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
