#!/bin/sh

# python-pysaml2: pysaml2: SAML2 for Python (Keystone federation)
#
# pysaml2 7.5.4, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.
#
# Depends on python-openssl, the canonical Saphira package for the
# pyOpenSSL distribution (a duplicate python-pyopenssl was retired to avoid
# claiming the same OpenSSL/ module paths). Upstream pysaml2 7.5.4 pins
# pyopenssl<24.3.0; the published python-openssl is 25.3.0, so that pin is
# deliberately relaxed here (apk does not enforce it) and must be
# runtime-tested with federation enabled.

pkgname=python-pysaml2
pkgver=7.5.4
pkgrel=1
pkgarch=noarch
pkgdesc="pysaml2: SAML2 for Python (Keystone federation)"
license="Apache-2.0"
origin=pysaml2
repo=saphira
url=https://pypi.org/project/pysaml2/
source=https://files.pythonhosted.org/packages/6a/a0/24b70dbe8b6f0f6f6ef21f0f007526ed6c5c3d0de6c20bff2a261c2ec0d9/pysaml2-7.5.4.tar.gz
sha256=b827dcaab73c4f7fe001c945401eb442cfda5d22001cea50c20c138e9adeffea

depends="
    python3
    python-cryptography
    python-defusedxml
    python-openssl
    python-dateutil
    python-requests
    python-xmlschema
"
makedepends="
    python3
    python3-pip
    python-poetry-core
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
        --no-index \
        --no-deps \
        --ignore-installed \
        --no-build-isolation \
        --no-compile \
        --no-cache-dir \
        --root "$PKGDEST" \
        --prefix /usr \
        "$SRC"
}
