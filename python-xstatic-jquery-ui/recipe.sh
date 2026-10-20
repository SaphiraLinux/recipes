#!/bin/sh

# python-xstatic-jquery-ui: jquery-ui 1.13.0 (XStatic packaging standard)
#
# XStatic-jquery-ui 1.13.0.2, vendored sdist, installed offline into system
# site-packages. Frontend asset bundle for Horizon; pure data.

pkgname=python-xstatic-jquery-ui
pkgver=1.13.0.2
pkgrel=1
pkgarch=noarch
pkgdesc="jquery-ui 1.13.0 (XStatic packaging standard) (OpenStack 2026.2 closure)"
license='MIT'
origin=XStatic-jquery-ui
repo=saphira
url=https://pypi.org/project/XStatic-jquery-ui/
source=https://files.pythonhosted.org/packages/7f/32/499fa843a3b1ffb856b380fce8fca2f6e39864d13d1cf5558f8f761bef45/xstatic_jquery_ui-1.13.0.2.tar.gz
sha256=11b2aa7eaa1ad69c6e594cae11a817a8fa171cec9ceb82ae2ca4ba7e93d5ae43

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
