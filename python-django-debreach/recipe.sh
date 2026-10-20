#!/bin/sh

# python-django-debreach: Adds middleware to give some added protection against the BREACH attack in Django.
#
# django-debreach 2.1.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-django-debreach
pkgver=2.1.0
pkgrel=1
pkgarch=noarch
pkgdesc="Adds middleware to give some added protection against the BREACH attack in Django. (OpenStack 2026.2 closure)"
license='BSD-3-Clause'
origin=django-debreach
repo=saphira
url=https://pypi.org/project/django-debreach/
source=https://files.pythonhosted.org/packages/1f/1a/2bc5970d6b848c7ff4ab2932493a8e25bbed47f7668e4c3338152defc01a/django-debreach-2.1.0.tar.gz
sha256=aeac9f43e0ea97830bed69cb309ad5746b5ed2b9dce733ac4c136c8e16a7d6e5

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
