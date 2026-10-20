#!/bin/sh

# python-xstatic-jsencrypt: JSEncrypt 2.3.1 (XStatic packaging standard)
#
# XStatic-JSEncrypt 2.3.1.2, vendored sdist, installed offline into system
# site-packages. Frontend asset bundle for Horizon; pure data.

pkgname=python-xstatic-jsencrypt
pkgver=2.3.1.2
pkgrel=1
pkgarch=noarch
pkgdesc="JSEncrypt 2.3.1 (XStatic packaging standard) (OpenStack 2026.2 closure)"
license='MIT'
origin=XStatic-JSEncrypt
repo=saphira
url=https://pypi.org/project/XStatic-JSEncrypt/
source=https://files.pythonhosted.org/packages/7b/b2/06e674689dab222d0490d94e6c39bc5a93016a90332ee47e16f3177a2eae/xstatic_jsencrypt-2.3.1.2.tar.gz
sha256=19d726ff82fc27177496bea5c2d39ed33f809763ea37ca1a51e30faf48338a1b

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
