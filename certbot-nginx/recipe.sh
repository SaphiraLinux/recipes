#!/bin/sh

pkgname=certbot-nginx
pkgver=5.7.0
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Nginx plugin for certbot (certbot monorepo)"
license="Apache-2.0"
origin=certbot-nginx
repo=saphira
url=https://pypi.org/project/certbot-nginx/
source=https://files.pythonhosted.org/packages/02/79/b56c9b175864adacbef4d615bb76ff1b4aa3b583859703d0a0a4a582ffe5/certbot_nginx-5.7.0.tar.gz
sha256=3ef5b924a4dc68a3c61f31306249d6f99a65da317574bf56c816159629a73b3d

# certbot[nginx] extra: PyOpenSSL + pyparsing.
depends="
    python3
    certbot
    python-openssl
    pyparsing
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
