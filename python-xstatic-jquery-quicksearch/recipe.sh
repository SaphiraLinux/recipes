#!/bin/sh

# python-xstatic-jquery-quicksearch: JQuery.quicksearch 2.0.3 (XStatic packaging standard)
#
# XStatic-JQuery.quicksearch 2.0.3.3, vendored sdist, installed offline into system
# site-packages. Frontend asset bundle for Horizon; pure data.

pkgname=python-xstatic-jquery-quicksearch
pkgver=2.0.3.3
pkgrel=1
pkgarch=noarch
pkgdesc="JQuery.quicksearch 2.0.3 (XStatic packaging standard) (OpenStack 2026.2 closure)"
license='MIT'
origin=XStatic-JQuery.quicksearch
repo=saphira
url=https://pypi.org/project/XStatic-JQuery.quicksearch/
source=https://files.pythonhosted.org/packages/35/e9/85f50e4b0c5e111272657b21c012f54728703bf6bbc6632252e49f1d9c7d/xstatic_jquery_quicksearch-2.0.3.3.tar.gz
sha256=71d7fc84a73fd5da4ae08d54ada83c6e1d809465c50106a94d72747f36023a3c

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
