#!/bin/sh

# python-xstatic-jasmine: Jasmine 2.4.1 (XStatic packaging standard)
#
# XStatic-Jasmine 2.4.1.3, vendored sdist, installed offline into system
# site-packages. Frontend asset bundle for Horizon; pure data.

pkgname=python-xstatic-jasmine
pkgver=2.4.1.3
pkgrel=1
pkgarch=noarch
pkgdesc="Jasmine 2.4.1 (XStatic packaging standard) (OpenStack 2026.2 closure)"
license='MIT'
origin=XStatic-Jasmine
repo=saphira
url=https://pypi.org/project/XStatic-Jasmine/
source=https://files.pythonhosted.org/packages/07/3c/5f80d9e47d9e19c866d32d40f6d005a536fbc0ee9ecb14953f09748f6d93/xstatic_jasmine-2.4.1.3.tar.gz
sha256=a1c4cee5382ee418c08c1387b7492e2fbf9e4fca73fc6c3c727822a5173b3aa9

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
