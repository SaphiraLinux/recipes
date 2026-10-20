#!/bin/sh

# python-xstatic-bootstrap-scss: Bootstrap-SCSS 3.4.1 (XStatic packaging standard)
#
# XStatic-Bootstrap-SCSS 3.4.1.1, vendored sdist, installed offline into system
# site-packages. Frontend asset bundle for Horizon; pure data.

pkgname=python-xstatic-bootstrap-scss
pkgver=3.4.1.1
pkgrel=1
pkgarch=noarch
pkgdesc="Bootstrap-SCSS 3.4.1 (XStatic packaging standard) (OpenStack 2026.2 closure)"
license='MIT'
origin=XStatic-Bootstrap-SCSS
repo=saphira
url=https://pypi.org/project/XStatic-Bootstrap-SCSS/
source=https://files.pythonhosted.org/packages/43/fe/17db0077d0f916a64c77e9ef16f5745a098a9405ab5187e70b6806a681d9/xstatic_bootstrap_scss-3.4.1.1.tar.gz
sha256=489ec477174b67dbb9f1f76f9ae4745ede3290010c4af02af7ec6e01b5452dc0

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
