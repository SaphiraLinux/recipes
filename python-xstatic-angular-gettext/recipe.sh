#!/bin/sh

# python-xstatic-angular-gettext: Angular-Gettext 2.4.1 (XStatic packaging standard)
#
# XStatic-Angular-Gettext 2.4.1.1, vendored sdist, installed offline into system
# site-packages. Frontend asset bundle for Horizon; pure data.

pkgname=python-xstatic-angular-gettext
pkgver=2.4.1.1
pkgrel=1
pkgarch=noarch
pkgdesc="Angular-Gettext 2.4.1 (XStatic packaging standard) (OpenStack 2026.2 closure)"
license='MIT'
origin=XStatic-Angular-Gettext
repo=saphira
url=https://pypi.org/project/XStatic-Angular-Gettext/
source=https://files.pythonhosted.org/packages/57/55/5a3ed20db7bed4b13be74590d6079f5ec6620059957ceb8c7611b08a46b2/xstatic_angular_gettext-2.4.1.1.tar.gz
sha256=b13d39c3b65886d7ad99558dabc38c6c33e44323d7c44b6a0f8a5e903d3dee7d

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
