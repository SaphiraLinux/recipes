#!/bin/sh

# python-django: A high-level Python web framework that encourages rapid development and clean, pragmatic design.
#
# Django 5.2.9, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-django
pkgver=5.2.9
pkgrel=1
pkgarch=noarch
pkgdesc="A high-level Python web framework that encourages rapid development and clean, pragmatic design. (OpenStack 2026.2 closure)"
license='BSD-3-Clause'
origin=Django
repo=saphira
url=https://pypi.org/project/Django/
source=https://files.pythonhosted.org/packages/eb/1c/188ce85ee380f714b704283013434976df8d3a2df8e735221a02605b6794/django-5.2.9.tar.gz
sha256=16b5ccfc5e8c27e6c0561af551d2ea32852d7352c67d452ae3e76b4f6b2ca495

depends="
    python3
    python-asgiref
    python-sqlparse"

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
