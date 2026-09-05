#!/bin/sh

pkgname=python-openssl
pkgver=25.3.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Python wrapper module around the OpenSSL library (pyOpenSSL)"
license="Apache-2.0"
origin=pyopenssl
repo=saphira
url=https://pypi.org/project/pyOpenSSL/
source=https://files.pythonhosted.org/packages/80/be/97b83a464498a79103036bc74d1038df4a7ef0e402cfaf4d5e113fb14759/pyopenssl-25.3.0.tar.gz
sha256=c981cb0a3fd84e8602d7afc209522773b94c1c2446a3c710a75b06fe1beae329

# Requires cryptography>=45.0.7,<47 at runtime (not yet ported).
depends="
    python3
    python-cryptography
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
