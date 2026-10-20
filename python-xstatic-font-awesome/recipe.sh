#!/bin/sh

# python-xstatic-font-awesome: Font-Awesome 6.2.1 (XStatic packaging standard)
#
# XStatic-Font-Awesome 6.2.1.2, vendored sdist, installed offline into system
# site-packages. Frontend asset bundle for Horizon; pure data.

pkgname=python-xstatic-font-awesome
pkgver=6.2.1.2
pkgrel=1
pkgarch=noarch
pkgdesc="Font-Awesome 6.2.1 (XStatic packaging standard) (OpenStack 2026.2 closure)"
license='MIT'
origin=XStatic-Font-Awesome
repo=saphira
url=https://pypi.org/project/XStatic-Font-Awesome/
source=https://files.pythonhosted.org/packages/c9/1c/164ed35ac7c31ae8e5d7a69de101eb46481553cb1be7cc5fb248ae8bd822/xstatic_font_awesome-6.2.1.2.tar.gz
sha256=9f3cb2f038fad7d352722375d3f25af346da9ee093ed9dc2c8c46bd911ab1971

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
