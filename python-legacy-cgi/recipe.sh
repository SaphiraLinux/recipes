#!/bin/sh

# python-legacy-cgi: legacy-cgi: the removed cgi module, backported for Python 3.13+
#
# legacy-cgi 2.6.4, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-legacy-cgi
pkgver=2.6.4
pkgrel=1
pkgarch=noarch
pkgdesc="legacy-cgi: the removed cgi module, backported for Python 3.13+"
license="PSF-2.0"
origin=legacy-cgi
repo=saphira
url=https://pypi.org/project/legacy-cgi/
source=https://files.pythonhosted.org/packages/f4/9c/91c7d2c5ebbdf0a1a510bfa0ddeaa2fbb5b78677df5ac0a0aa51cf7125b0/legacy_cgi-2.6.4.tar.gz
sha256=abb9dfc7835772f7c9317977c63253fd22a7484b5c9bbcdca60a29dcce97c577

depends="
    python3
"
makedepends="
    python3
    python3-pip
    python-hatchling
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
