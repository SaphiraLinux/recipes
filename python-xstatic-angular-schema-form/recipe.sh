#!/bin/sh

# python-xstatic-angular-schema-form: Angular-Schema-Form 0.8.13 (XStatic packaging standard)
#
# XStatic-Angular-Schema-Form 0.8.13.1, vendored sdist, installed offline into system
# site-packages. Frontend asset bundle for Horizon; pure data.

pkgname=python-xstatic-angular-schema-form
pkgver=0.8.13.1
pkgrel=1
pkgarch=noarch
pkgdesc="Angular-Schema-Form 0.8.13 (XStatic packaging standard) (OpenStack 2026.2 closure)"
license='MIT'
origin=XStatic-Angular-Schema-Form
repo=saphira
url=https://pypi.org/project/XStatic-Angular-Schema-Form/
source=https://files.pythonhosted.org/packages/13/22/86b29b02c0cb252ef7ceb2d60bf515efe5a57283dbce39cf2d46026184dd/xstatic_angular_schema_form-0.8.13.1.tar.gz
sha256=e6aef27aeb4aed6eb0b32839e9f08bbc304d348b155c122e30580c4a6f80556b

depends="
    python3
    python-xstatic
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
