#!/bin/sh

# python-django-appconf: A helper class for handling configuration defaults of packaged apps gracefully.
#
# django-appconf 1.2.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-django-appconf
pkgver=1.2.0
pkgrel=1
pkgarch=noarch
pkgdesc="A helper class for handling configuration defaults of packaged apps gracefully. (OpenStack 2026.2 closure)"
license='BSD-3-Clause'
origin=django-appconf
repo=saphira
url=https://pypi.org/project/django-appconf/
source=https://files.pythonhosted.org/packages/d1/a2/e58bec8d7941b914af52a67c35b5709eceed2caa2848f28437f1666ed668/django_appconf-1.2.0.tar.gz
sha256=15a88d60dd942d6059f467412fe4581db632ef03018a3c183fb415d6fc9e5cec

depends="
    python3
    python-django"

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
