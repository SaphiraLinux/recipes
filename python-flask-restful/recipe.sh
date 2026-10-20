#!/bin/sh

# python-flask-restful: Flask-RESTful: REST APIs with Flask (Keystone API)
#
# Flask-RESTful 0.3.10, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-flask-restful
pkgver=0.3.10
pkgrel=1
pkgarch=noarch
pkgdesc="Flask-RESTful: REST APIs with Flask (Keystone API)"
license="BSD-3-Clause"
origin=Flask-RESTful
repo=saphira
url=https://pypi.org/project/Flask-RESTful/
source=https://files.pythonhosted.org/packages/c0/ce/a0a133db616ea47f78a41e15c4c68b9f08cab3df31eb960f61899200a119/Flask-RESTful-0.3.10.tar.gz
sha256=fe4af2ef0027df8f9b4f797aba20c5566801b6ade995ac63b588abf1a59cec37

depends="
    python3
    python-aniso8601
    python-flask
    python-six
    python-pytz
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
