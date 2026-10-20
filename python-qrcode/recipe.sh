#!/bin/sh

# python-qrcode: QR Code image generator
#
# qrcode 8.2, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-qrcode
pkgver=8.2
pkgrel=1
pkgarch=noarch
pkgdesc="QR Code image generator (OpenStack 2026.2 closure)"
license='BSD-3-Clause'
origin=qrcode
repo=saphira
url=https://pypi.org/project/qrcode/
source=https://files.pythonhosted.org/packages/8f/b2/7fc2931bfae0af02d5f53b174e9cf701adbb35f39d69c2af63d4a39f81a9/qrcode-8.2.tar.gz
sha256=35c3f2a4172b33136ab9f6b3ef1c00260dd2f66f858f24d88418a015f446506c

depends="
    python3
"

makedepends="
    python3
    python3-pip
    python-poetry-core
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
