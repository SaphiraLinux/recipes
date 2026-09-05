#!/bin/sh

pkgname=python-requests
pkgver=2.34.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Python HTTP library for humans"
license="Apache-2.0"
origin=requests
repo=saphira
url=https://pypi.org/project/requests/
source=https://files.pythonhosted.org/packages/ac/c3/e2a2b89f2d3e2179abd6d00ebd70bff6273f37fb3e0cc209f48b39d00cbf/requests-2.34.2.tar.gz
sha256=f288924cae4e29463698d6d60bc6a4da69c89185ad1e0bcc4104f584e960b9ed

depends="
    python3
    python-charset-normalizer
    python-urllib3
    idna
    certifi
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
