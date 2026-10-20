#!/bin/sh

# python-django-compressor: Compresses linked and inline JavaScript or CSS into single cached files.
#
# django-compressor 4.6.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-django-compressor
pkgver=4.6.0
pkgrel=1
pkgarch=noarch
pkgdesc="Compresses linked and inline JavaScript or CSS into single cached files. (OpenStack 2026.2 closure)"
license='MIT'
origin=django-compressor
repo=saphira
url=https://pypi.org/project/django-compressor/
source=https://files.pythonhosted.org/packages/a2/e4/c6d87b1341d744ceafa85eeceb2adabb1c62b795b8207cbc580fb70df8f4/django_compressor-4.6.0.tar.gz
sha256=c7478feab98f3368780591f9ee28a433350f5277dd28811f7f710f5bc6dff3c0

depends="
    python3
    python-django
    python-django-appconf
    python-rcssmin
    python-rjsmin"

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
