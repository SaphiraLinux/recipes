#!/bin/sh

# python-xstatic-jquery-migrate: JQuery-Migrate 3.3.2 (XStatic packaging standard)
#
# XStatic-JQuery-Migrate 3.3.2.2, vendored sdist, installed offline into system
# site-packages. Frontend asset bundle for Horizon; pure data.

pkgname=python-xstatic-jquery-migrate
pkgver=3.3.2.2
pkgrel=1
pkgarch=noarch
pkgdesc="JQuery-Migrate 3.3.2 (XStatic packaging standard) (OpenStack 2026.2 closure)"
license='MIT'
origin=XStatic-JQuery-Migrate
repo=saphira
url=https://pypi.org/project/XStatic-JQuery-Migrate/
source=https://files.pythonhosted.org/packages/49/d5/c63dbead064ce4d8d01c43a687d343f45dc0c1c3ce725454efe5bf4a1f0e/xstatic_jquery_migrate-3.3.2.2.tar.gz
sha256=641ca995d838c151dfdcadbb0eb8d2e7d9855bcd398c77c36cc65c3e79f57228

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
