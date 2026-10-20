#!/bin/sh

# python-werkzeug: Werkzeug: WSGI utilities (Flask/Keystone)
#
# Werkzeug 3.1.8, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-werkzeug
pkgver=3.1.8
pkgrel=1
pkgarch=noarch
pkgdesc="Werkzeug: WSGI utilities (Flask/Keystone)"
license="BSD-3-Clause"
origin=Werkzeug
repo=saphira
url=https://pypi.org/project/Werkzeug/
source=https://files.pythonhosted.org/packages/dd/b2/381be8cfdee792dd117872481b6e378f85c957dd7c5bca38897b08f765fd/werkzeug-3.1.8.tar.gz
sha256=9bad61a4268dac112f1c5cd4630a56ede601b6ed420300677a869083d70a4c44

depends="
    python3
    python-markupsafe
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
