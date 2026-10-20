#!/bin/sh

# python-amqp: amqp: low-level AMQP 0.9.1 client (oslo.messaging rabbit driver)
#
# amqp 5.3.1, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-amqp
pkgver=5.3.1
pkgrel=1
pkgarch=noarch
pkgdesc="amqp: low-level AMQP 0.9.1 client (oslo.messaging rabbit driver)"
license="BSD-3-Clause"
origin=amqp
repo=saphira
url=https://pypi.org/project/amqp/
source=https://files.pythonhosted.org/packages/79/fc/ec94a357dfc6683d8c86f8b4cfa5416a4c36b28052ec8260c77aca96a443/amqp-5.3.1.tar.gz
sha256=cddc00c725449522023bad949f70fff7b48f0b1ade74d170a6f10ab044739432

depends="
    python3
    python-vine
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
