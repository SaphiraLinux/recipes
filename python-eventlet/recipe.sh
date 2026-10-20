#!/bin/sh

# python-eventlet: eventlet: concurrent networking library (oslo.service)
#
# eventlet 0.41.2, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-eventlet
pkgver=0.41.2
pkgrel=1
pkgarch=noarch
pkgdesc="eventlet: concurrent networking library (oslo.service)"
license="MIT"
origin=eventlet
repo=saphira
url=https://pypi.org/project/eventlet/
source=https://files.pythonhosted.org/packages/eb/e8/6a3a23a3b85ed129b21309c6eca873d833855e63879cd72b9dac20d9b76a/eventlet-0.41.2.tar.gz
sha256=721b86b77fca33a735598292022ac6feef99747bf48f52defdada6b572acd5af

depends="
    python3
    python-dnspython
    python-greenlet
"
makedepends="
    python3
    python3-pip
    python-hatchling
    setuptools
    python-hatch-vcs
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
