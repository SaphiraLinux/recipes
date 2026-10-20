#!/bin/sh

# python-xstatic-term-js: term.js 0.0.7 (XStatic packaging standard)
#
# XStatic-term.js 0.0.7.1, vendored sdist, installed offline into system
# site-packages. Frontend asset bundle for Horizon; pure data.

pkgname=python-xstatic-term-js
pkgver=0.0.7.1
pkgrel=1
pkgarch=noarch
pkgdesc="term.js 0.0.7 (XStatic packaging standard) (OpenStack 2026.2 closure)"
license='MIT'
origin=XStatic-term.js
repo=saphira
url=https://pypi.org/project/XStatic-term.js/
source=https://files.pythonhosted.org/packages/f6/a3/8db32c905411dbb30ad5762d08bcd765ad6c357e0fc9f62ff1e3a927b94b/xstatic_term_js-0.0.7.1.tar.gz
sha256=afda65f80b08fafb056ef216b47d2d1b31b2f607c956abb8c6b186d2727041ae

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
