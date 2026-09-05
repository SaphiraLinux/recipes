#!/bin/sh

pkgname=acme
pkgver=5.7.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Python ACME protocol library (certbot monorepo)"
license="Apache-2.0"
origin=acme
repo=saphira
url=https://pypi.org/project/acme/
source=https://files.pythonhosted.org/packages/8d/53/2e79e7d1c5384414d4670f02729601cf23e61fe13b7b99471d02c620ddbe/acme-5.7.0.tar.gz
sha256=4be4fe6cf3809c3988d75fa1213ce8e784d9d5d8380cac63c2dca555e105653d

# Requires cryptography>=43.0.0 at runtime (via python-openssl/josepy, not yet ported).
depends="
    python3
    python-cryptography
    python-josepy
    python-openssl
    python-pyrfc3339
    python-requests
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
