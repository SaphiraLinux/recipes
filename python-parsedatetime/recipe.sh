#!/bin/sh

pkgname=python-parsedatetime
pkgver=2.6
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Python human-readable date/time parser"
license="Apache-2.0"
origin=parsedatetime
repo=saphira
url=https://pypi.org/project/parsedatetime/
source=https://files.pythonhosted.org/packages/a8/20/cb587f6672dbe585d101f590c3871d16e7aec5a576a1694997a3777312ac/parsedatetime-2.6.tar.gz
sha256=4cb368fbb18a0b7231f4d76119165451c8d2e35951455dfee97c62a87b04d455

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
