#!/bin/sh

# python-statsd: statsd: simple statsd client (oslo.middleware dependency)
#
# statsd 4.0.1, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-statsd
pkgver=4.0.1
pkgrel=1
pkgarch=noarch
pkgdesc="statsd: simple statsd client (oslo.middleware dependency)"
license="MIT"
origin=statsd
repo=saphira
url=https://pypi.org/project/statsd/
source=https://files.pythonhosted.org/packages/27/29/05e9f50946f4cf2ed182726c60d9c0ae523bb3f180588c574dd9746de557/statsd-4.0.1.tar.gz
sha256=99763da81bfea8daf6b3d22d11aaccb01a8d0f52ea521daab37e758a4ca7d128

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
