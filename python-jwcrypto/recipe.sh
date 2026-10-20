#!/bin/sh

# python-jwcrypto: Implementation of JOSE Web standards
#
# jwcrypto 1.5.8, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-jwcrypto
pkgver=1.5.8
pkgrel=1
pkgarch=noarch
pkgdesc="Implementation of JOSE Web standards (OpenStack 2026.2 closure)"
license='LGPL-3.0-only'
origin=jwcrypto
repo=saphira
url=https://pypi.org/project/jwcrypto/
source=https://files.pythonhosted.org/packages/de/7e/53c14813521693e931e420d9db00efe317419ff194495903bce03402275e/jwcrypto-1.5.8.tar.gz
sha256=c3d7114b6f6e65b52f6b7da817eb8cb8423e1da31e1ef13508447c81ecbdcc34

depends="
    python3
    python-cryptography
    typing-extensions"

makedepends="
    python3
    python3-pip
    python-hatchling
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
