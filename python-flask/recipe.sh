#!/bin/sh

# python-flask: Flask: WSGI microframework (Keystone REST API)
#
# Flask 3.1.3, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-flask
pkgver=3.1.3
pkgrel=1
pkgarch=noarch
pkgdesc="Flask: WSGI microframework (Keystone REST API)"
license="BSD-3-Clause"
origin=Flask
repo=saphira
url=https://pypi.org/project/Flask/
source=https://files.pythonhosted.org/packages/26/00/35d85dcce6c57fdc871f3867d465d780f302a175ea360f62533f12b27e2b/flask-3.1.3.tar.gz
sha256=0ef0e52b8a9cd932855379197dd8f94047b359ca0a78695144304cb45f87c9eb

depends="
    python3
    python-blinker
    click
    python-itsdangerous
    python-jinja2
    python-markupsafe
    python-werkzeug
"
makedepends="
    python3
    python3-pip
    python-flit-core
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
