#!/bin/sh

# python-aniso8601: aniso8601: ISO 8601 date/time parser (Flask-RESTful)
#
# aniso8601 10.0.1, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-aniso8601
pkgver=10.0.1
pkgrel=1
pkgarch=noarch
pkgdesc="aniso8601: ISO 8601 date/time parser (Flask-RESTful)"
license="BSD-3-Clause"
origin=aniso8601
repo=saphira
url=https://pypi.org/project/aniso8601/
source=https://files.pythonhosted.org/packages/8b/8d/52179c4e3f1978d3d9a285f98c706642522750ef343e9738286130423730/aniso8601-10.0.1.tar.gz
sha256=25488f8663dd1528ae1f54f94ac1ea51ae25b4d531539b8bc707fed184d16845

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
