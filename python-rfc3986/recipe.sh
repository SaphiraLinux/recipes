#!/bin/sh

# python-rfc3986: rfc3986: URI parsing/validation (oslo.config dependency)
#
# rfc3986 2.0.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-rfc3986
pkgver=2.0.0
pkgrel=1
pkgarch=noarch
pkgdesc="rfc3986: URI parsing/validation (oslo.config dependency)"
license="Apache-2.0"
origin=rfc3986
repo=saphira
url=https://pypi.org/project/rfc3986/
source=https://files.pythonhosted.org/packages/85/40/1520d68bfa07ab5a6f065a186815fb6610c86fe957bc065754e47f7b0840/rfc3986-2.0.0.tar.gz
sha256=97aacf9dbd4bfd829baad6e6309fa6573aaf1be3f6fa735c8ab05e46cecb261c

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
